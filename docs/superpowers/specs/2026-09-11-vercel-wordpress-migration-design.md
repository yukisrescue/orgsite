# Vercel Landing Page WordPress Migration

**Date:** 2026-09-11

**Status:** Approved design, pending written-spec review

**Issue:** YUKI-ndkaskno

**Source:** <https://yukis-rescue-org.vercel.app/>

## Problem

The current public WordPress export at `www.yukisrescue.org` does not use the
new landing-page design published on Vercel. The Vercel page must become the
editable WordPress home page without retaining a runtime dependency on Vercel
or changing the existing publication architecture.

## Decision

Reproduce the Vercel landing page as native content in the existing Yuki's
Rescue WordPress block theme. WordPress remains the authoring system, Simply
Static produces the public artifact, Git records each publication, and
Cloudflare Workers serves production.

An iframe or redirect to Vercel is rejected because it would not make the page
editable in WordPress. A new headless WordPress and Next.js stack is rejected
because it adds a second application and deployment path without providing a
benefit for this single-page site.

## Fidelity Contract

The Vercel page as observed on 2026-09-11 is the visual and content source of
truth. The migration preserves:

- all current text, including text that identifies itself as placeholder copy;
- the logo artwork, organization name, address, phone number, nonprofit status,
  EIN, and 2026 dates;
- the sticky translucent header and its About, Mission, Get Involved, and
  Contact anchor links;
- the hero, About, Mission, Get Involved, Contact, and footer sections in their
  current order;
- the Rescue, Rehabilitation, and Rehoming items and the Adopt, Volunteer, and
  Donate cards;
- the existing buttons and their anchor, telephone, and map destinations;
- the cream, charcoal, muted beige, lavender, and sage palette;
- Inter body text and Fraunces headings, including the italic hero heading;
- the desktop and mobile arrangements, spacing, borders, rounded elements,
  glow, shadow, hover states, and subtle reveal transitions;
- smooth anchor scrolling, with reduced-motion behavior for visitors who
  request it; and
- the current title, description, social-sharing metadata, and NGO structured
  data, adapted only where WordPress requires a different representation.

The Vercel Contact section is not a form. This migration keeps it as an address,
telephone link, and call button. The existing contact-form Worker remains in
the repository but is not connected to this landing page.

## WordPress Architecture

The existing `theme/yukis` block theme is extended instead of introducing a
second theme. WordPress-required template-hierarchy entry points retain their
reserved filenames. For example, WordPress must continue to discover
`templates/front-page.html` by that exact name.

All migration-specific names use the `vercel_` prefix. This includes custom
template parts, block-pattern identifiers, CSS classes, CSS custom properties,
script handles, and helper functions. Expected identifiers include
`vercel_header`, `vercel_landing`, and `vercel_footer`. No new unprefixed custom
component is introduced.

The standard `front-page.html` entry point composes the prefixed parts and the
editable home-page content. Structural presentation belongs to theme assets;
copy, links, and images remain normal editable WordPress blocks. Reusable
section patterns give designers a safe way to restore or duplicate a section
without editing HTML.

The theme stores the design tokens in `theme.json` and loads only the local
font files, stylesheet, and minimal behavior required by the page. It does not
copy the Vercel Next.js runtime, Tailwind output, hashed chunk names, or image
optimizer URLs.

## Components

### `vercel_header`

Contains the linked logo, desktop wordmark, sticky backdrop treatment, and
four anchor links. The mobile layout preserves the compact navigation shown by
the source site rather than introducing a new menu design.

### `vercel_landing`

Contains the five source sections as WordPress block markup. Each top-level
section has its source anchor ID. The logo image is stored locally in WordPress
or the theme and is never loaded from the Vercel deployment.

### `vercel_footer`

Contains the organization identity, address, phone number, 501(c)(3) statement,
EIN, copyright, and source spacing and border treatment.

### `vercel_styles`

Defines the source palette, typography, responsive layout, sticky-header
behavior, card and button states, and editor-compatible presentation. The
front-end stylesheet and block-editor stylesheet share the same tokens so the
editor remains a useful preview.

### `vercel_reveal`

Provides the source page's small entrance transitions without a framework.
Content remains visible when JavaScript is unavailable, and the behavior is
disabled when `prefers-reduced-motion: reduce` is active.

## Content and Publishing Flow

1. The migration-specific theme files and deterministic home-page seed are
   committed to this repository.
2. The theme is installed or synchronized to the existing authoring WordPress
   instance at `control.yukisrescue.org`.
3. The existing Home page is updated in place. Its identity is preserved so the
   configured static front page does not change.
4. A designer can edit source copy, links, and images with the block editor.
5. Simply Static exports the result, including local fonts, images, CSS, and
   JavaScript.
6. The existing guarded publish script commits the export and the existing
   GitHub workflow deploys it to Cloudflare Workers.

The current `/about/`, `/rescue/`, and `/feedback/` WordPress pages are outside
this homepage migration. They are not deleted or rewritten. The new header does
not link to them, matching the Vercel page. Their later retirement or redirect
is a separate, explicit decision.

## Failure Handling

- If a local asset is absent from the static export, publishing must fail using
  the existing missing-asset guard rather than deploy a broken page.
- If reveal JavaScript fails, all content remains visible and usable.
- If a source asset cannot be acquired, implementation stops and reports that
  exact asset; it is not silently replaced with a look-alike.
- If WordPress sanitizes or rewrites a block in a way that changes the layout,
  the structure moves into a prefixed theme pattern or part while its editable
  fields remain blocks.
- No live production publish occurs until the generated static artifact passes
  local fidelity and link checks.

## Verification

Verification compares the WordPress export with the Vercel source at desktop,
tablet, and mobile widths. Acceptance requires:

- all source sections, words, links, metadata, and structured data are present;
- the palette, type hierarchy, layout, spacing, logo sizing, card treatments,
  and responsive ordering are materially indistinguishable from the source;
- all four header anchors land below the sticky header;
- telephone and map links have the same destinations as the source;
- the block editor can change representative text, a link, and the logo without
  editing theme code;
- the static export contains every referenced local asset and contains no
  `_next`, `vercel.app`, or authoring-host asset dependency;
- keyboard navigation, visible focus, semantic heading order, image alternative
  text, and reduced-motion behavior are preserved;
- theme-focused checks and existing publisher and Worker tests pass; and
- a production smoke test confirms the deployed home page and its assets after
  publication.

## Rollout and Recovery

Implementation first produces and verifies a local/static preview. Publication
uses the existing versioned Cloudflare path only after review. Git records the
entire generated-site change, so rollback remains the existing revert and
redeploy process. No Vercel configuration is removed during this work.

## Non-goals

- Rewriting or approving the placeholder wording
- Adding a contact form, adoption database, donation processor, or CMS feature
- Redesigning the Vercel layout or introducing new responsive behavior
- Migrating the Vercel Next.js application itself
- Deleting the Vercel deployment or legacy WordPress pages
- Changing WordPress hosting, authentication, backups, static export, GitHub
  Actions, DNS, or Cloudflare production architecture
