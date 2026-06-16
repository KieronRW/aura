# AURA Project State

## Overview

<!-- Project overview to be filled in -->

## Engineering Principles

- **Think commercially at all times** — AURA is a commercial product, not a hobby project. Every architectural decision must scale to 10, 100, 1000+ installations without manual per-unit intervention. The current 3-unit Mauritius deployment is the starting point, not the ceiling.
- **No per-unit manual operations** — if a fix, update, or configuration change requires SSH-ing into individual units, it's not a scalable solution. Everything must be remotely manageable via the app or automated.
- **Act as a senior software engineer** — propose solutions that a commercial IoT product company would be proud of. Consider maintainability, observability, failure modes, and upgrade paths.
