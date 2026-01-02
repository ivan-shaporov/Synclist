# Shared Shopping List

> **Disclaimer**: This project is 100% vibecoded.

A simple, persistent, real-time shopping list web app that works on Android and iPhone without installation.

## Features

* **Shared State**: Syncs between multiple users in near real-time.
* **Smart Sorting**: Checked items move to the bottom; unchecked items move to the top.
* **Zero Backend Code**: Connects directly from the browser to Azure Table Storage using a SAS token.
* **Offline Capable**: Works with a local fallback list if no connection is configured.
* **Privacy Focused**: Your data lives in your own Azure Storage account.

## Architecture

* **Frontend**: Single HTML file (`index.html`) with vanilla JavaScript.
* **Backend**: Azure Table Storage (No API servers, Functions, or App Services required).
* **Security**: Shared Access Signature (SAS) token injected at build time.

## Setup

### 1. Azure Setup

1. Create an **Azure Storage Account**.
2. Create a **Table** (e.g., named `shopping-list`).
3. Generate a **SAS Token** for the table with the following permissions:
    * **Allowed Services**: Table
    * **Allowed Resource Types**: Service, Container, Object
    * **Allowed Permissions**: Read, Add, Update, Delete (Write is not strictly needed if you use Update/Merge, but good to have).
    * **Expiry**: Set it for a long duration (e.g., 1 year).
4. Copy the **Table Service SAS URL**. It should look like:
    `https://<your-account>.table.core.windows.net/shopping-list?sv=...&sig=...`
5. **Enable CORS**: By default, browsers block requests to Azure Table Storage. You must enable CORS on your Storage Account.
    * Go to **CORS** settings in your Storage Account (under Settings > Resource sharing or CORS).
    * Add a rule for the **Table service**:
        * **Allowed origins**: `*` (or your specific domain like `https://myapp.pages.dev`).
        * **Allowed methods**: `GET`, `PUT`, `MERGE`, `OPTIONS`.
        * **Allowed headers**: `*`.
        * **Exposed headers**: `*`.
        * **Max age**: `86400`.

### 2. Build the App

To keep your secret SAS token out of source control, we use a template system.

1. Clone the repo.
2. Run the build script with your SAS URL:

    ```powershell
    .\build.ps1 "YOUR_FULL_SAS_URL_HERE"
    ```

3. This will generate an `index.html` file (which is git-ignored).

### 3. Deploy / Use

* **Local**: Open `index.html` directly in your browser.
* **Host**: Upload `index.html` to any static host (GitHub Pages, Azure Static Web Apps, Netlify, etc.). **Note**: Since the SAS token is embedded in the file, ensure the hosted URL is private or you trust the people you share it with.
* **Azure Blob**: You can upload `index.html` to an Azure Blob Storage container and share it via a **Blob SAS URL**.
  * *Important*: This Blob SAS URL is just for accessing the HTML file. It is different from the **Table SAS URL** that is embedded inside the code.
* **First Run**: If your Azure Table is empty, the app will automatically populate it with a default set of items on the first run.

## Managing Items

* **Editing**: The app currently does not support adding, editing, or deleting items via the UI.
* **Admin**: You can manage the list items (add new ones, change text, delete old ones) directly in the Azure Table using tools like [Microsoft Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer/) or the Azure Portal.

## Development

* Edit `index.template.html` for code changes.
* Run `.\build.ps1 <sas-token>` to regenerate `index.html` for testing.
