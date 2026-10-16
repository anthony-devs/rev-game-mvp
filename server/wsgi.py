import os

from app import ENV_FILES, create_app

app = create_app()

if __name__ == "__main__":
    # Local development server:  python wsgi.py
    # (Production uses gunicorn, see the Dockerfile.)
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8080"))
    print(f"\n  REV Games server  ->  http://{'localhost' if host in ('127.0.0.1', '0.0.0.0') else host}:{port}")
    print(f"  env files loaded  ->  {', '.join(ENV_FILES) or 'none (using the shell environment)'}")
    print(f"  firebase project  ->  {os.environ.get('FIREBASE_PROJECT_ID', 'rev-games')}")
    if os.environ.get("ADMIN_KEY"):
        print(f"  admin dashboard   ->  http://localhost:{port}/admin\n")
    else:
        print("  admin dashboard   ->  OFF (set ADMIN_KEY to turn it on)\n")
    # threaded: crash rounds keep a live event stream open per player
    app.run(host=host, port=port, threaded=True, debug=False)
