import os

from console import create_app

app = create_app()

if __name__ == "__main__":
    host, port = os.environ.get("HOST", "127.0.0.1"), int(os.environ.get("PORT", "9090"))
    print(f"\n  REV Games developer console -> http://{host}:{port}\n  (binds to localhost by default; put it behind HTTPS before exposing it)\n")
    app.run(host=host, port=port, threaded=True, debug=False)
