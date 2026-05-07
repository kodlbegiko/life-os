# Life OS

Life OS is a local-first personal operating system prototype with two surfaces:

- Native macOS app built with SwiftUI and SwiftData.
- Public Legacy Web demo deployable to Vercel as a read-only FastAPI demo.

This public repository contains sanitized demo data only. It does not include private user data, local SwiftData stores, app bundles, runtime logs, backups, or Apple Calendar exports.

## Native macOS App

```bash
xcodebuild test -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug -derivedDataPath dist/DerivedData -destination 'platform=macOS,arch=arm64'
./script/build_and_run.sh --verify
```

## Legacy Web Demo

Local development:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
LIFE_OS_PUBLIC_DEMO=1 uvicorn backend.main:app --reload
```

Open `http://127.0.0.1:8000`.

Public demo behavior:

- `GET /api/dashboard` works with sanitized demo data.
- `GET /api/replan-week` works with sanitized demo data.
- Mutating endpoints and Apple Calendar endpoints are disabled in public demo mode.

## Vercel

```bash
npx vercel@latest deploy --prod --yes
```

The Vercel deployment uses `api/index.py` and `vercel.json` to run the FastAPI app as a Python function.
