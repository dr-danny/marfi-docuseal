<h1 align="center" style="border-bottom: none">
  <div>
    <img alt="MARFI" src="public/marfi-logo.png" width="80" />
    <br>
    MARFI Secure eSign
  </div>
</h1>
<h3 align="center">
  MARFI-maintained OSS fork of DocuSeal for secure document filling and signing
</h3>
<p align="center">
  This repository is based on the <a href="https://github.com/docusealco/docuseal">DocuSeal open source project</a> and retains its attribution.
</p>
<p>
MARFI Secure eSign is a private, self-hosted document signing service based on DocuSeal OSS. Create PDF forms, send signing requests, and retain documents under MARFI-controlled infrastructure.
</p>

## Features
- PDF form fields builder (WYSIWYG)
- 12 field types available (Signature, Date, File, Checkbox etc.)
- Multiple submitters per document
- Automated emails via SMTP
- Files storage on disk or AWS S3, Google Storage, Azure Cloud
- Automatic PDF eSignature
- PDF signature verification
- Users management
- Mobile-optimized
- 7 UI languages with signing available in 14 languages
- API and Webhooks for integrations
- Easy to deploy in minutes

## MARFI OSS additions
- MARFI branding and noindex defaults for the private portal
- Free internal admin, editor, and viewer roles
- Safe rendering of OSS-compatible HTML notification templates

Enterprise and Pro components are not included. Existing integrations must be validated against this fork before production use.

## Upstream Pro features not included
- Company logo and white-label controls
- Automated reminders
- Invitation and identity verification via SMS
- Conditional fields and formulas
- Bulk send with CSV, XLSX spreadsheet import
- SSO / SAML
- Template creation with HTML API ([Guide](https://www.docuseal.com/guides/create-pdf-document-fillable-form-with-html-api))
- Template creation with PDF or DOCX and field tags API ([Guide](https://www.docuseal.com/guides/use-embedded-text-field-tags-in-the-pdf-to-create-a-fillable-form))
- Embedded signing form ([React](https://github.com/docusealco/docuseal-react), [Vue](https://github.com/docusealco/docuseal-vue), [Angular](https://github.com/docusealco/docuseal-angular) or [JavaScript](https://www.docuseal.com/docs/embedded))
- Embedded document form builder ([React](https://github.com/docusealco/docuseal-react), [Vue](https://github.com/docusealco/docuseal-vue), [Angular](https://github.com/docusealco/docuseal-angular) or [JavaScript](https://www.docuseal.com/docs/embedded))
- [Learn more](https://www.docuseal.com/pricing)

## Deploy

#### Docker

```sh
docker run --name marfi-docuseal -p 3000:3000 -v ./data:/data ghcr.io/dr-danny/marfi-docuseal:marfi-oss-3.2.3
```

PostgreSQL is selected with `DATABASE_URL`. Keep SMTP, storage, webhook, and integration secrets outside the repository.

## License and corresponding source

Distributed under the AGPLv3 License with Section 7(b) Additional Terms. See [LICENSE](LICENSE) and [LICENSE_ADDITIONAL_TERMS](LICENSE_ADDITIONAL_TERMS) for more information.
This fork retains DocuSeal's interactive attribution and copyright notices. MARFI modifications are available in this repository as the corresponding source for users of the hosted service.
Unless otherwise noted, upstream files are © 2023-2026 DocuSeal LLC. MARFI modifications are © 2026 MARFI Systems, Inc.

