# Editing the Yuki's Rescue website

This is for the people who write and design the site.

## The short version

You edit at **control.yukisrescue.org**. The public site is
**www.yukisrescue.org**. They are two different places, and changes you make do
not appear on the public site until you click **Generate Static Files**.

## Signing in

There are two doors:

**Door 1 — Cloudflare.** Go to `https://control.yukisrescue.org/wp-admin/`.
You will be asked for your email address, then sent a one-time code OR sign
in with Google. This gate keeps the internet out.

You will not do this every time. Once through, you stay signed in for 24 hours.

**Door 2 — WordPress.** Now the familiar WordPress login appears. Use the
username and password Mario gave you.

Change your password once you are in: top-right menu → Edit Profile → New
Password.

**If you get stuck at door 1**, your email address is not on the allowed list.
Ask Mario. **If you get stuck at door 2**, ask Mario to reset your password —
the "Lost your password?" link does not work on this site, because it cannot
send email.

The following sections describe site operations.

## Editing a page

**Pages** in the left sidebar → click a page → edit → **Update**.

Four pages exist today: Home, About Us, Rescue a Dog, and Feedback. Three of
them still say "under construction" and are waiting for real content.

## Changing how the site looks

**Appearance → Editor** opens the visual designer. Colours, fonts, spacing and
layout are all editable there, and changes apply across the whole site.

The colour palette is already set up with the site's colours, so picking from
the swatches keeps things consistent. You can change the palette itself in
**Styles → Colours** if the brand changes.

You will not break anything permanently. Every change is reversible, and there
is a nightly backup.

## Publishing to the live site

**Settings → Simply Static → Generate Static Files.**

Wait for it to finish, then wait about another minute. The live site updates by
itself — usually under a minute after the export finishes, occasionally two.

There is no second button, no approval step, no waiting on anyone. What you
publish goes live.

**That is worth sitting with for a moment.** There is no preview and no review.
If you publish something wrong, it is on the public website until someone fixes
it. Mario can undo any publish in under a minute, so tell him quickly rather
than trying to fix it under pressure.

## Adding a new page

Create it as normal, then add it to the menu: **Appearance → Editor →
Navigation**.

Then publish as above. New pages are picked up automatically — you do not need
to tell anyone or configure anything.

## Adding images

**Media → Add New**, or upload directly while editing a page. Images are
published along with everything else.

Please resize large photos before uploading. A photo straight off a phone can be
several megabytes, which makes the site slow for people on poor connections —
often exactly the people trying to reach a rescue.

## What you cannot do

- Install plugins or themes
- Edit theme code
- Add or remove users

This is deliberate. It means you cannot accidentally break the site in a way
that is hard to undo, which is what makes it safe to let you publish without
review.

## Plugins and what works live

There is a fuller **Editor & Designer Handbook** inside WordPress itself —
Pages → *Editor & Designer Handbook*. It is a private page, so it never appears
on the public site. Read it once; it covers the things below in detail.

The short version:

- **Plugins are site-wide or not installed at all.** This is a single WordPress
  site, so nothing can be enabled "just for me". Only Mario can install one.
- **Anything that needs the server to react when a visitor clicks will not work
  on the live site** — forms from plugins, comments, search, logins. The public
  site is plain saved files with no WordPress behind it.
- **Constant Contact Forms is installed, and its forms will not work publicly.**
  Use Constant Contact's own hosted form or embed code instead.
- Layout, styling, block, gallery and SEO plugins are all fine.

## When something is wrong

**A change is not showing on the live site.** Did you click Generate Static
Files after saving? That is nearly always it. If you did, wait two minutes and
hard-refresh.

**You cannot sign in.** See the two doors above — work out which one is
refusing you, and say which when you ask for help. It makes a big difference.

**Something looks broken on the live site.** Tell Mario immediately. Undoing a
publish takes about a minute. Do not try to fix it by publishing repeatedly.

**A page you created is missing from the live site.** This should not happen —
it is handled automatically. If it does, say so, because it means something is
wrong beyond your change.
