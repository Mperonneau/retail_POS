# retail_pos

Retail POS — BizManager Haiti retail module

## Deploy on Render

This repo includes a [`render.yaml`](render.yaml) blueprint for a **static site** (`build/web`) with SPA rewrites for `go_router`.

1. Push this project to a Git host Render can connect to (GitHub, GitLab, or Bitbucket).
2. In [Render Dashboard](https://dashboard.render.com), create a **Blueprint** from the repo, or add a **Static Site** with:
   - **Build command:** same as `buildCommand` in `render.yaml`
   - **Publish directory:** `build/web`
3. For CLI/API automation, set `RENDER_API_KEY` (Account Settings → API Keys) or run `render login` after installing the [Render CLI](https://render.com/docs/cli).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
