#!/home/groot/.local/share/journal-venv/bin/python3
import os
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: check_watchlist_streaming.py <target_markdown_file_to_append>")
        sys.exit(1)

    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "update_watchlist.py")
    os.execv(script, [script, "--append-diary", sys.argv[1]])


if __name__ == "__main__":
    main()
