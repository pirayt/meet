# CLAUDE.md

This is a fork of La Suite Meet (LiveKit-based video conferencing) run as a private service for online psychotherapy sessions. Talk to the owner in Russian. Start with `docs/fork/README.md` (what the fork is, how it differs from upstream, how to sync) and `docs/fork/decisions.md` (why things are the way they are).

## Non-negotiables

- Privacy first. Therapy sessions are confidential. Never add telemetry, third-party calls, logging of media/chat content or anything that stores audio/video/text outside our server without an explicit decision recorded in `docs/fork/decisions.md`.
- The repository is public. Never commit secrets, server addresses, open ports, firewall state or other details of the live deployment. Those stay in chat.
- The deployed frontend image is built from `main` and tagged `latest`. Do not merge to `main` changes that require a newer backend unless the server upgrade is coordinated.

## Working on the code

- Base: upstream release tag (see `docs/fork/README.md`). Keep our diff small: prefer overriding tokens, config or small hooks over rewriting upstream components.
- Commit messages follow upstream style: `<gitmoji>(<scope>) <summary>`, title ≤ 80 chars.
- Frontend checks before pushing (in `src/frontend`): `npm ci && npm run check && npm run lint && npm run build`.
- Any new UI string goes to `src/frontend/src/locales/en` and must also be translated in `ru/` (Russian plurals: `_one`, `_few`, `_many`, `_other`). Backend strings: `src/backend/locale/ru_RU/LC_MESSAGES/django.po`.
- Record non-obvious decisions in `docs/fork/decisions.md`; feature designs live in `docs/fork/<feature>.md`.
