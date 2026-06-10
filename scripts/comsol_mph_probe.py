import argparse
import sys


def safe_call(label, func):
    try:
        value = func()
    except Exception as exc:
        print(f"{label}: unavailable ({exc})")
        return None

    print(f"{label}: {value}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Connect to a running COMSOL Server with mph and print a read-only model summary."
    )
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=2038)
    parser.add_argument("--model", help="Expected .mph path, used only for display.")
    args = parser.parse_args()

    try:
        import mph
    except Exception as exc:
        print(f"ERROR: Python package 'mph' is not importable: {exc}", file=sys.stderr)
        print("Install/use the Python environment that has mph configured for COMSOL.", file=sys.stderr)
        return 2

    print(f"Connecting to COMSOL Server at {args.host}:{args.port} ...")
    try:
        client = mph.Client(host=args.host, port=args.port)
    except TypeError:
        client = mph.Client(args.host, args.port)
    except Exception as exc:
        print(f"ERROR: Could not connect to COMSOL Server: {exc}", file=sys.stderr)
        return 3

    if args.model:
        print(f"Expected GUI-visible model: {args.model}")

    models = safe_call("Server models", client.models)
    if not models:
        print(
            "No models were reported by mph. If the GUI shows the model, it may be in a different server session.",
            file=sys.stderr,
        )
        return 4

    model = models[0]
    print("")
    print("Read-only summary for first server model:")
    safe_call("Name", lambda: model.name())
    safe_call("File", lambda: model.file())
    safe_call("Parameters", lambda: model.parameters())
    safe_call("Studies", lambda: model.studies())
    safe_call("Datasets", lambda: model.datasets())
    safe_call("Exports", lambda: model.exports())

    print("")
    print("Probe completed without modifying or saving the model.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
