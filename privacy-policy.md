# Privacy Policy — Tidyr

**Last updated: 2026-04-26**

## Overview

Tidyr is a macOS app that helps you organize files using Google Gemini AI. Your privacy is important to us. This policy explains what data the app handles and how.

## Data We Collect

**We collect no data.** Tidyr has no servers, no analytics, no telemetry, and no accounts.

## Your API Key

- Your Gemini API key is stored in the macOS Keychain on your device only.
- The key is sent directly from your device to Google's Gemini API to process your requests.
- Tidyr never receives, stores, or transmits your API key to any other party.

## File Data

- Tidyr reads files and folder names from directories you explicitly select.
- File names and the command you type are sent to Google Gemini to generate an organization plan.
- **File contents are never read or transmitted** — only names and paths.
- No data is retained by Tidyr after the session ends. All local state (sources, history) is stored on your device in `~/Library/Application Support/Tidyr/`.

## Third-Party Services

Tidyr uses **Google Gemini API** to generate file organization suggestions. When you run an analysis, file names from the selected folder are sent to Google. Please review [Google's Privacy Policy](https://policies.google.com/privacy) for information on how Google handles this data.

No other third-party services are used.

## Sandboxing

Tidyr runs in Apple's macOS App Sandbox. It can only access folders you explicitly grant access to. It has no access to the rest of your file system, your contacts, your camera, your microphone, or any other sensitive resources.

## Changes

If this policy changes, the updated version will be posted at this URL with a new "Last updated" date.

## Contact

Questions? Open an issue at [github.com/GaiMSdev/tidyr](https://github.com/GaiMSdev/tidyr) or email raakanin@gmail.com.
