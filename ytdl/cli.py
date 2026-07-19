import shutil

import click
import yt_dlp
from rich.console import Console
from rich.progress import Progress, BarColumn, DownloadColumn, TransferSpeedColumn, TimeRemainingColumn

console = Console()


class RichProgressHook:
    """Progress hook that renders yt-dlp download progress with rich."""

    def __init__(self):
        self.progress = None
        self.task_id = None
        self._started = False

    def __call__(self, d):
        if d["status"] == "downloading":
            if not self._started:
                self.progress = Progress(
                    "[progress.description]{task.description}",
                    BarColumn(),
                    DownloadColumn(),
                    TransferSpeedColumn(),
                    TimeRemainingColumn(),
                    console=console,
                )
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                self.progress.start()
                self.task_id = self.progress.add_task("Downloading", total=total)
                self._started = True

            downloaded = d.get("downloaded_bytes", 0)
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            if total:
                self.progress.update(self.task_id, completed=downloaded, total=total)

        elif d["status"] == "finished":
            if self.progress:
                self.progress.stop()
                self._started = False
            console.print("[green]Download complete[/green]")


@click.command()
@click.argument("url")
@click.option("-o", "--output", default="%(title)s.%(ext)s", help="Output filename template")
@click.option("-f", "--format", "fmt", default=None, help="Format selector (e.g. best, 720p, bestaudio)")
@click.option("--audio-only", is_flag=True, help="Download audio only (mp3)")
@click.option("--list-formats", is_flag=True, help="List available formats")
@click.option("--subtitles", is_flag=True, help="Also download subtitles")
@click.option("--output-dir", "-d", default=".", help="Destination directory")
@click.option("--playlist", is_flag=True, help="Download the entire playlist")
@click.option(
    "--cookies-from-browser",
    default="safari",
    help="Read cookies from a browser (e.g. chrome, safari, firefox, edge, brave). Pass '' to disable.",
)
@click.option("--cookies", default=None, help="Path to a cookies.txt file")
@click.option(
    "--player-client",
    default="default,web,mweb,ios,android",
    help="YouTube player clients to try (comma-separated)",
)
def main(url, output, fmt, audio_only, list_formats, subtitles, output_dir, playlist, cookies_from_browser, cookies, player_client):
    """Download a YouTube video from URL."""
    progress_hook = RichProgressHook()

    # Detect JS runtimes for YouTube extraction.
    js_runtimes = {}
    for runtime in ("deno", "node"):
        path = shutil.which(runtime)
        if path:
            js_runtimes[runtime] = {"path": path}

    ydl_opts = {
        "outtmpl": f"{output_dir}/{output}",
        "progress_hooks": [progress_hook],
        "noplaylist": not playlist,
        "quiet": True,
        "no_warnings": True,
    }
    if js_runtimes:
        ydl_opts["js_runtimes"] = js_runtimes
    ydl_opts["remote_components"] = {"ejs": "github"}

    if cookies_from_browser:
        ydl_opts["cookiesfrombrowser"] = (cookies_from_browser,)
    if cookies:
        ydl_opts["cookiefile"] = cookies

    if player_client:
        clients = [c.strip() for c in player_client.split(",") if c.strip()]
        ydl_opts["extractor_args"] = {"youtube": {"player_client": clients}}

    if list_formats:
        ydl_opts["listformats"] = True
        ydl_opts["quiet"] = False
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])
        return

    if audio_only:
        ydl_opts["format"] = "bestaudio/best"
        ydl_opts["postprocessors"] = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        }]
    elif fmt:
        ydl_opts["format"] = fmt
    else:
        ydl_opts["format"] = (
            "bestvideo[ext=mp4]+bestaudio[ext=m4a]/"
            "bestvideo+bestaudio/"
            "best[ext=mp4]/best"
        )

    if subtitles:
        ydl_opts["writesubtitles"] = True
        ydl_opts["writeautomaticsub"] = True
        ydl_opts["subtitleslangs"] = ["ja", "en"]

    console.print(f"[bold blue]URL:[/bold blue] {url}")

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            if info and not list_formats:
                title = info.get("title", "unknown")
                duration = info.get("duration", 0)
                mins, secs = divmod(duration, 60) if duration else (0, 0)
                console.print(f"[bold green]Title:[/bold green] {title}")
                console.print(f"[bold green]Duration:[/bold green] {mins}m{secs}s")
                console.print()

            ydl.download([url])
    except yt_dlp.utils.DownloadError as e:
        console.print(f"[bold red]Error:[/bold red] {e}")
        raise SystemExit(1)
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted[/yellow]")
        raise SystemExit(130)


if __name__ == "__main__":
    main()
