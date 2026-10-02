# Contributing a lab

Thanks for helping people learn! A lab is a folder of YAML and shell scripts. You don't need to touch
the server. The full reference is [docs/authoring.md](docs/authoring.md); this is the short path.

1. **Scaffold:** `node scripts/new-lab.js <track> <lab-id> "Title"` (new track names create a track).
   Add the lab id to the `labs:` list in `labs/<track>/track.yaml` — that list sets the order.
2. **Write it** in `labs/<track>/<lab-id>/`: `lab.yaml` (steps), `checks/<step>.sh`,
   `solutions/<step>.sh`, and optionally `setup.sh`.
3. **Try it:** `docker compose up`, then edit and refresh — labs are re-read on every page load.
4. **Validate:** `docker compose run --rm labs node scripts/validate-labs.js --strict [track/lab]`.
   For every task it checks that the check **fails before** the solution and **passes after**.
   CI runs the same command; a lab that doesn't pass can't merge.
5. Open a PR — the template has a checklist.

## Style guide

- **One concept per lab, 5–15 minutes, 3–7 tasks.** Small steps beat clever ones.
- Each task says *exactly* what to do. The `hint` is a nudge, not the answer; the check's failure
  message (first line it prints) should say what's still missing.
- **Grade state, not keystrokes.** Prefer "the file exists / the branch is merged / mode is 600".
  Use `ran` (command history) only when there's nothing to inspect, e.g. "run `ls -l`".
- Checks must be **tolerant of valid alternatives** (`mv` or `cp`+`rm`; `-la` or `-l -a`) and never
  require the learner to type your exact command when the outcome is what matters.
- No network, no `sudo`, nothing that needs a package that isn't in the image. Need a tool?
  Open an issue / add it to the `Dockerfile` in the same PR.
- Scripts are plain bash and must be safe: they run as the learner's unprivileged user inside the sandbox.
  No `curl | sh`, no writing outside `$LAB_HOME`.
- Lesson text is markdown (bold, `code`, lists, fenced blocks, https links). Raw HTML is escaped.
- Keep it friendly: explain the *why* in lessons, and welcome beginners.
- Don't name other products or platforms in lab text or comments (`npm run check:hygiene` checks). Stick to the tools the lab teaches.

## Ground rules

- Be kind: see the [Code of Conduct](CODE_OF_CONDUCT.md). Security issues go through [SECURITY.md](SECURITY.md), never a public issue.
- By contributing you agree your work is released under the repository's [MIT License](LICENSE).
- Never commit secrets, AWS account IDs or ARNs. Pull requests run CI (tests, every lab, a compose smoke test) and must pass before merge.
