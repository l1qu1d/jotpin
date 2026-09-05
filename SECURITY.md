# Security policy

JotPin is a local Omarchy shell plugin. It stores notes and settings on the
user's machine and does not provide a network service, account system, or
telemetry endpoint. A flaw can still affect local files, shell execution,
plugin loading, bundled workers, or a user's rendered note, so please report
those issues privately.

## Reporting a vulnerability

During pre-release development, security fixes target the latest `main` branch.
Older snapshots are not maintained separately. Include the affected commit in
reports so the maintainer can check whether an update already resolves it.

Use [GitHub private vulnerability reporting](https://github.com/l1qu1d/jotpin/security/advisories/new)
when available, or open the repository's **Security** tab and choose
**Report a vulnerability**.

If that route is unavailable, ask a maintainer for a private reporting channel.
An issue requesting a contact method must contain no vulnerability details.
Never put vulnerability details in an issue, pull request, discussion, commit,
or release note before coordinated disclosure, regardless of repository
visibility.

Please include the affected JotPin version or commit, Omarchy and Quickshell
versions, the impact, and a small reproduction when it is safe to share. Remove
real note contents, credentials, personal paths, and other sensitive data.
Avoid testing against another person's machine or data.

## What happens next

The maintainer will review the report, confirm its impact and affected
versions, and coordinate a fix or mitigation. Disclosure timing will be
coordinated after affected users have a reasonable path to update. Reporter
credit can be included when requested.

There is no guaranteed response time. If a report does not receive a response,
use the same private route to follow up without reposting the vulnerability in
public.
