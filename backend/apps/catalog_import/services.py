"""Catalogue import jobs. The analysis runs on a worker thread and the
register polls the job; rows live in the database so a poll can land on
any server process."""

from __future__ import annotations

import logging
import secrets
import threading
from datetime import timedelta

from django.core.exceptions import ValidationError
from django.db import close_old_connections, transaction
from django.utils import timezone

from apps.accounts.models import StaffMember
from apps.catalog.models import Category, Product, ProductOptionChoice, ProductOptionGroup
from apps.catalog.services import record_initial_stock
from apps.common.exceptions import ApiError
from apps.common.money import money

from .engine import CatalogImportError, _decode_files, _known_categories, extract_catalog
from .models import ImportJob

log = logging.getLogger(__name__)
# A job still "running" after this died with its process (deploy, restart).
STALE_AFTER = timedelta(minutes=20)
INTERRUPTED = "L'analyse a été interrompue par un redémarrage du serveur. Touchez Analyser pour recommencer."


def _options(body: dict) -> tuple[str, int, str, list[str]]:
    currency = str(body.get("currency_mode") or "htg").lower()
    if currency not in ("htg", "usd", "mixed"):
        raise ApiError("Choisissez HTG, USD ou mixte.")
    try:
        rate = int(float(body.get("usd_rate") or 0))
    except (TypeError, ValueError) as exc:
        raise ApiError("Taux USD invalide.") from exc
    if currency in ("usd", "mixed") and rate <= 0:
        raise ApiError("Indiquez combien de gourdes valent 1 dollar.")
    return currency, rate, str(body.get("owner_note") or "")[:2000], _known_categories(body.get("known_categories"))


def start_job(body: dict, *, business=None, staff=None, run_async: bool = True) -> ImportJob:
    currency, rate, note, known = _options(body)
    try:
        files = _decode_files(body.get("files"))
    except CatalogImportError as exc:
        raise ApiError(exc.message, exc.status) from exc
    if business is not None and not known:
        known = list(Category.objects.filter(business=business).values_list("name", flat=True)[:200])
    job = ImportJob.objects.create(id=secrets.token_urlsafe(12), business=business, created_by=staff,
                                   progress="Lecture du document…", file_names=[name for name, _, _ in files][:20])
    args = (job.pk, files, note, currency, rate, known)
    if run_async:
        threading.Thread(target=_run, args=args, name=f"catalog-import-{job.pk}", daemon=True).start()
    else:
        _run(*args)
    return job


def _run(job_id, files, note, currency, rate, known) -> None:
    def on_progress(message: str) -> None:
        ImportJob.objects.filter(pk=job_id, status=ImportJob.RUNNING).update(progress=message[:120],
                                                                             updated_at=timezone.now())

    try:
        draft, report = extract_catalog(files, owner_note=note, currency_mode=currency, usd_rate=rate,
                                        known_categories=known, on_progress=on_progress)
        _finish(job_id, status=ImportJob.SUCCEEDED, draft=draft, report=report, progress="Terminé.")
    except CatalogImportError as exc:
        _finish(job_id, status=ImportJob.FAILED, error=exc.message[:300], progress="Échec.")
    except Exception:
        log.exception("catalog import %s failed", job_id)
        _finish(job_id, status=ImportJob.FAILED, error="L'analyse a échoué. Réessayez.", progress="Échec.")
    finally:
        close_old_connections()


def _finish(job_id, **fields) -> None:
    ImportJob.objects.filter(pk=job_id).update(finished_at=timezone.now(), updated_at=timezone.now(), **fields)


def get_job(job_id: str, *, business=None) -> ImportJob:
    job = ImportJob.objects.filter(pk=str(job_id)[:32]).first()
    if job is None or (business is not None and job.business_id != business.pk):
        raise ApiError(INTERRUPTED, 404)
    if job.status == ImportJob.RUNNING and job.updated_at < timezone.now() - STALE_AFTER:
        _finish(job.pk, status=ImportJob.FAILED, error=INTERRUPTED, progress="Échec.")
        job.refresh_from_db()
    return job


def job_view(job: ImportJob) -> dict:
    return {
        "id": job.pk,
        "status": job.status,
        "progress": job.progress,
        "error": job.error,
        "draft": job.draft,
        "report": job.report,
        "created_at": int(job.created_at.timestamp()),
        "applied_at": int(job.applied_at.timestamp()) if job.applied_at else None,
    }


@transaction.atomic
def apply_draft(job: ImportJob, actor, draft: dict | None = None) -> dict:
    """Create the reviewed products. The register may send back an edited draft."""
    job = ImportJob.objects.select_for_update().get(pk=job.pk)
    if job.status != ImportJob.SUCCEEDED:
        raise ApiError("L'analyse n'est pas terminée.", 409)
    if job.applied_at is not None:
        raise ApiError("Ce brouillon a déjà été importé.", 409)
    draft = draft if isinstance(draft, dict) and draft.get("categories") else job.draft
    business = actor.business
    created = 0
    skipped = 0
    categories = {c.name.lower(): c for c in Category.objects.filter(business=business)}
    barcodes = set(Product.objects.filter(business=business).exclude(barcode="").values_list("barcode", flat=True))
    for cat in (draft.get("categories") or [])[:200]:
        name = str(cat.get("name") or "Autres").strip()[:60] or "Autres"
        category = categories.get(name.lower())
        if category is None:
            category = Category.objects.create(business=business, name=name, sort_order=len(categories))
            categories[name.lower()] = category
        for item in (cat.get("items") or [])[:2000]:
            item_name = str(item.get("name") or "").strip()[:120]
            price = money(item.get("price_htg"))
            barcode = str(item.get("barcode") or "").strip()[:64]
            if not item_name or price <= 0 or (barcode and barcode in barcodes):
                skipped += 1
                continue
            mode = item.get("sale_mode") if item.get("sale_mode") in ("piece", "roll", "case") else "piece"
            product = Product(
                business=business, name=item_name, category=category, description=str(item.get("description") or "")[:600],
                barcode=barcode, price_htg=price, cost_htg=money(item.get("cost_htg")),
                discount_percent=money(item.get("discount_percent")), sale_mode=mode,
                roll_price_htg=money(item.get("roll_price_htg")), roll_width=int(item.get("roll_width") or 0),
                min_width=int(item.get("min_width") or 0), case_price_htg=money(item.get("case_price_htg")),
                units_per_case=int(item.get("units_per_case") or 0), unit=str(item.get("unit") or "")[:12],
                track_stock=item.get("stock") is not None,
                stock_quantity=max(0, int(item.get("stock") or 0)),
            )
            try:
                product.clean()
            except ValidationError:
                skipped += 1
                continue
            product.save()
            record_initial_stock(product, actor if isinstance(actor, StaffMember) else None)
            for g_index, group in enumerate((item.get("option_groups") or [])[:6]):
                kind = group.get("kind") if group.get("kind") in dict(ProductOptionGroup.KINDS) else "other"
                row = ProductOptionGroup.objects.create(product=product, name=str(group.get("name") or "Options")[:60],
                                                        kind=kind,
                                                        required=bool(group.get("required")),
                                                        multiple=bool(group.get("multiple")), sort_order=g_index)
                ProductOptionChoice.objects.bulk_create([
                    ProductOptionChoice(group=row, name=str(c.get("name") or "")[:60],
                                        price_delta_htg=money(c.get("price_delta_htg")), sort_order=c_index)
                    for c_index, c in enumerate((group.get("choices") or [])[:20]) if c.get("name")
                ])
            if barcode:
                barcodes.add(barcode)
            created += 1
    job.applied_at = timezone.now()
    job.save(update_fields=["applied_at", "updated_at"])
    return {"created": created, "skipped": skipped}
