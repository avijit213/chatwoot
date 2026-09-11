# hoichoi fork of Chatwoot

Fork point: `chatwoot/chatwoot@develop`. Upstream is wired as the `upstream`
remote; `origin` is our fork.

## Why this fork exists

To theme the **widget** (the chat UI inside the iframe) without hoichoi calling
Chatwoot's HTTP endpoints ourselves. Chatwoot's own client talks to its own
backend, so endpoint changes ship on both sides together and are never our
problem.

## What we changed

Deliberately as close to nothing as possible, so rebasing stays cheap.

| File | Change |
| --- | --- |
| `app/views/widgets/show.html.erb` | +7 lines: load a stylesheet from `WIDGET_THEME_URL` |
| `public/hoichoi/widget-theme.css` | our theme (not upstream code) |

The hook is env-gated: with `WIDGET_THEME_URL` unset the page is byte-identical
to upstream, so the fork is inert by default.

## Deploying

Set `WIDGET_THEME_URL` to wherever the stylesheet is hosted. Pointing it at a
CDN rather than `public/` means restyling needs no Chatwoot rebuild or
redeploy — republish the CSS and reload.

Running this fork means building and publishing your own image rather than
pulling `chatwoot/chatwoot:<tag>`, and owning its security-patch cadence.

## What this approach cannot do

Themes Chatwoot's screens; it cannot add screens that are not there. Absent
from the Chatwoot widget and therefore **not** achievable in CSS:

- Home / Messages / Help tab bar
- "Hello there." hero
- Search + FAQ accordion
- Movies / Shows / Latest catalog rails

Those exist in hoichoi's own panel (`@hoichoi/support` in
Hoichoi.SharedClientPlatform). This fork is for brand colour, type and spacing
on Chatwoot's layout.

## Rebasing

    git fetch upstream
    git rebase upstream/develop

Conflicts should be limited to the 7 lines in `show.html.erb`. The CSS is ours
and never conflicts, but it targets Chatwoot's DOM: prefer their hand-written
semantic classes (`.chat-bubble`, `.user-message`, `.message-content`) over
Tailwind utilities, which churn between releases. Re-check the theme visually
after a major upgrade — it degrades rather than breaks.

## Licensing

Everything outside `enterprise/` is MIT; `enterprise/` (which includes Captain)
is under the Chatwoot Enterprise License and needs a valid subscription for
production use. Our changes are outside `enterprise/`. Confirm with Chatwoot
that your subscription covers a self-built image before running one.
