# ai-next 🚀

`ai-next` is an advanced AI pipeline orchestration script designed to enforce strict, multi-agent development workflows (e.g., Design -> Implement -> Test -> Review).

By breaking down the development process into rigid phases and using Git empty commits as a communication channel ("Bucket Relay" system), it prevents AI agents from generating chaotic spaghetti code and forces them to follow proper software engineering principles.

## Features
- **Strict Phase Enforcement**: Enforces sequential execution (`-design`, `-implement`, `-test`, `-review`).
- **Multi-Agent Relay**: Easily hand off tasks between different AI backends (`-to codex`, `-to claude`, `-to agy`).
- **Git-Backed Memory**: Agents read previous Git commit messages (`git log`), `git diff`, and `git status` to understand the context of the previous phase.
- **Rule Enforcement**: Automatically injects project-specific design rules (`AI_DESIGN_RULES.md`) during the DESIGN phase.

## Usage

Create a design document using an architect AI (e.g., Codex or Claude):
```bash
ai-next -to codex -design "Design the new Search API"
```

Pass the baton to the implementation AI to write the code based on the design:
```bash
ai-next -to codex -implement "Implement the API based on the design document"
```

Have a reviewer AI run tests and generate a report:
```bash
ai-next -to claude -test "Run pytest and verify boundary conditions"
```

## Setup
Just link the script to your PATH:
```bash
ln -sf /path/to/ai-next/ai-next.sh ~/.local/bin/ai-next
```
