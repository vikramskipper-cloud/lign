# APP 035 — Organisation disciplines and automatic brief questions

Approved studio owners choose their firm's design disciplines during welcome-email password setup, before their organisation and first workspace are created. Multiple disciplines are supported; General design provides an industry-neutral core. Invited team members and external stakeholders are not asked to choose a firm's industry. The fallback organisation/first-workspace creation screen captures the same choice.

The organisation stores its discipline defaults and a version for checked owner/admin updates. **Organisation overview → Organisation settings** lets existing firms configure or update them. New unsaved briefs automatically start with core questions plus the selected discipline questions. Project-specific changes remain under the collapsed **Adjust questions for this project** control. An existing saved brief or agreement is never regenerated when the organisation default changes.

Activation wraps the existing access-only flow. It retains approved-request and verified-email checks, creates the organisation/workspace and saves its profile atomically. Invalid initial configuration rolls the activation transaction back. Retrying activation or resetting a password preserves an already configured organisation. The ordinary sign-in step after setting a password remains.

`get_project_brief` supplies defaults only after checking project access, so project stakeholders can receive the appropriate starting questions without gaining organisation access. Changing the organisation profile requires an active owner/admin membership and the expected version. Anonymous access and cross-tenant reads remain denied.

Migration: `20261114010000_app_035_organization_disciplines.sql`. The six-field request-access form remains unchanged.

Validation: `tests/access/organization-disciplines.mjs` covers atomic activation, retries, invalid input, general/multiple disciplines, first-workspace creation, tenant/role boundaries, optimistic locking and saved brief preservation. `tests/access/organization-disciplines-browser.mjs` verifies welcome password setup, automatic questions, project-only overrides, owner settings and mobile layout. The existing project brief browser flow opens the optional adjustment control when explicitly testing industry overrides.
