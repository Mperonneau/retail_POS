from __future__ import annotations

from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts import roles
from apps.accounts.permissions import require
from apps.payments.legacy import LegacyOpen

from . import services


class ImportJobsView(APIView):
    permission_classes = [require(roles.CATALOG_MANAGE)]
    throttle_scope = "catalog_import"

    def post(self, request):
        job = services.start_job(request.data, business=request.user.business, staff=request.user)
        return Response({"id": job.pk, "status": job.status}, status=202)


class ImportJobView(APIView):
    permission_classes = [require(roles.CATALOG_MANAGE)]

    def get(self, request, job_id: str):
        return Response(services.job_view(services.get_job(job_id, business=request.user.business)))


class ImportApplyView(APIView):
    permission_classes = [require(roles.CATALOG_MANAGE)]

    def post(self, request, job_id: str):
        job = services.get_job(job_id, business=request.user.business)
        return Response(services.apply_draft(job, request.user, request.data.get("draft")))


class LegacyImportJobsView(APIView):
    """Same payload as the payments server's /catalog/imports."""

    authentication_classes: list = []
    permission_classes = [LegacyOpen]
    throttle_scope = "catalog_import"

    def post(self, request):
        job = services.start_job(request.data)
        return Response({"id": job.pk, "status": job.status})


class LegacyImportJobView(APIView):
    authentication_classes: list = []
    permission_classes = [LegacyOpen]

    def get(self, request, job_id: str):
        job = services.get_job(job_id)
        if job.business_id is not None:
            return Response({"error": services.INTERRUPTED}, status=404)
        view = services.job_view(job)
        view.pop("applied_at", None)
        return Response(view)
