# transcript

A lightweight macOS command-line tool for downloading YouTube video transcripts. Written in Swift.

## Build

Requires Swift 6.1+ and macOS 13+.

```bash
swift build -c release
cp .build/release/transcript /usr/local/bin/
```

## Usage

```
transcript <video> [--format <format>] [--language <language>] [--clean] [--list] [--no-save]
```

### Arguments

| Argument | Description |
|---|---|
| `<video>` | YouTube video URL or 11-character video ID |

### Options

| Option | Default | Description |
|---|---|---|
| `-f, --format` | `text` | Output format: `text`, `srt`, or `json` |
| `-l, --language` | `en` | Caption language code |
| `--clean` | | Reformat transcript using AI (OpenAI) for readability |
| `--list` | | List available caption tracks and exit |
| `--no-save` | | Print to stdout only, do not save to file |
| `-h, --help` | | Show help |
| `--version` | | Show version |

### Examples

```bash
# Plain text transcript (default) — saved to ~/Documents/transcripts/YYYY/
transcript "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# Using a video ID directly
transcript dQw4w9WgXcQ

# Short URLs work too
transcript "https://youtu.be/dQw4w9WgXcQ"

# AI-formatted with section headings and proper paragraphs
transcript dQw4w9WgXcQ --clean

# SRT subtitle format
transcript dQw4w9WgXcQ -f srt

# JSON with timestamps
transcript dQw4w9WgXcQ -f json

# List available caption tracks
transcript dQw4w9WgXcQ --list

# Get Spanish transcript
transcript dQw4w9WgXcQ -l es

# Print only, don't save to file
transcript dQw4w9WgXcQ --no-save

# Pipe to clipboard
transcript dQw4w9WgXcQ --no-save | pbcopy
```

## Output

Each transcript is saved as a markdown file to `~/Documents/transcripts/YYYY/` partitioned by the video's publish year. The file includes a metadata header with title, channel, publish date, duration, view count, and a link to the original video.

Use `--no-save` to print to stdout without saving.

### Output Formats

**text** -- Plain transcript merged into paragraphs (default).

**srt** -- Standard SubRip subtitle format with sequence numbers and timestamps.

**json** -- Array of objects with `start` timestamp, `durationMs`, and `text` fields.

### AI Formatting (`--clean`)

The `--clean` flag sends the raw transcript through OpenAI (gpt-4.1-mini) to produce clean, readable markdown:

- Fixes punctuation, capitalization, and sentence boundaries
- Merges caption fragments into proper flowing paragraphs
- Adds `##` section headings at major topic shifts
- Uses `>` blockquotes for speaker changes and direct quotes
- Removes artifacts like `[music]` and `[applause]`

Requires `OPENAI_API_KEY` in your environment.

## How It Works

Uses YouTube's InnerTube API (ANDROID client) to fetch caption track metadata, then downloads and parses the caption data in JSON3 format. No YouTube API key or authentication required for public videos.

## Supported URL Formats

- `https://www.youtube.com/watch?v=VIDEO_ID`
- `https://youtu.be/VIDEO_ID`
- `https://www.youtube.com/embed/VIDEO_ID`
- `https://www.youtube.com/shorts/VIDEO_ID`
- `https://m.youtube.com/watch?v=VIDEO_ID`
- Raw 11-character video ID

## Limitations

- Public videos only (no age-restricted or private videos)
- Relies on YouTube's undocumented InnerTube API, which could change
- `--clean` requires an OpenAI API key and incurs API usage costs
