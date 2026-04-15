<div align="center">
    <img src="https://raw.githubusercontent.com/phellams/phellams-general-resources/main/logos/pslazy/dist/svg/pslazy-64x64.svg" width="128" height="128" alt="pslazy Logo" >
    <h1><strong>PSLazy</strong></h1>
    <p><b><i>Instant PowerShell Startup via Lazy-Loading</i></b></p>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)](https://github.com/yourusername/pslazy) [![PowerShell](https://img.shields.io/badge/PowerShell-7.0%2B-blue)](https://microsoft.com/powershell) [![Architecture](https://img.shields.io/badge/Arch-x64%20%7C%20ARM64-orange)](https://github.com/yourusername/pslazy)
</div>

<div align="center">
    <span>
        <a href="https://gitlab.com/phellams/pslazy#cmdlet-reference Features">CMDLET Reference</a> | 
        <a href="https://github.com/phellams/pslazy">GitHub</a> |
        <a href="https://www.powershellgallery.com/packages/PWSL">PSGallery</a> |
        <a href="https://chocolatey.org/packages/pslazy">Chocolatey</a>
    </span>
    <br>
</div>

## **What is PSLazy?**

**PSLazy** is a cross-platform orchestration engine designed to mitigate PowerShell profile bloat. By intercepting command calls via the `CommandNotFoundAction` hook and proxy functions, it auto-installs and loads modules, scripts, and dependencies only when they are actually needed. 

It uses **Static Analysis (AST)** to discover commands in raw scripts without executing them, ensuring your shell stays fast and responsive.

<details>
<summary><strong>📚Table of Contents</strong></summary>

- [What is PSLazy?](#what-is-pslazy)
- [**Key Features**](#key-features)
- [**Installation**](#installation)
  - [**Usage**](#usage)
  - [**API Reference**](#api-reference)
    - [`Register-LazyModule`](#register-lazymodule)
    - [`Get-LazyModule`](#get-lazymodule)
    - [`Unregister-LazyModule`](#unregister-lazymodule)
  - [**Example Output**](#example-output)
  - [**License**](#license)

</details>

## **Key Features**

* **Instant Startup**: Reduce shell load time to milliseconds by deferring `Import-Module` calls.
* **Auto-Provisioning**: Automatically fetch missing modules from **PSGallery**, **GitHub/GitLab Releases**, or **Git Clones**.
* **Package Manager Integration**: Native support for **Winget**, **Scoop**, and **Brew**.
* **Dependency Awareness**: Define a chain of modules that must load in sequence.
* **Architecture Gating**: Prevent incompatible tools from registering based on the host CPU (x64/ARM).
* **High-Density Logging**: Professional, color-coded console output for lifecycle events.

---

## **Installation**

Clone this repository into your PowerShell module path:

```powershell
# Windows
git clone https://github.com/phellams/pslazy "$HOME\Documents\PowerShell\Modules\PSLazy"

# macOS / Linux
git clone https://github.com/phellams/pslazy "$HOME/.local/share/powershell/Modules/PSLazy"
```

### **Usage**

Add the following to your `$PROFILE`. This is the **only** module you need to load eagerly.

```powershell
Import-Module PSLazy

# 1. Lazy-load from PSGallery
Register-LazyModule -Name 'Pester' -Source 'Pester' -PSModule -OutputExported

# 2. Lazy-load from Git Repo (Clones to local cache)
Register-LazyModule -Name 'PoshGit' -GitRepo 'https://github.com/dahlbyk/posh-git'

# 3. Lazy-load via Native Package Manager (Winget/Scoop/Brew)
Register-LazyModule -Name 'kubectl' -PackageId 'Kubernetes.kubectl' -Arch x64

# 4. Lazy-load with Dependencies
Register-LazyModule -Name 'Az.Accounts' -Source 'Az.Accounts' -PSModule
Register-LazyModule -Name 'SqlServer'   -Source 'SqlServer'   -PSModule -Dependencies 'Az.Accounts'
```

---

### **API Reference**

#### `Register-LazyModule`
Registers a definition for a module or binary.

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `-Name` | `string` | Unique identifier and command trigger name. |
| `-Source` | `string` | Local path or module name. |
| `-PSModule` | `switch` | If set, installs via `Install-Module` if missing. |
| `-GitRepo` | `string` | URL to clone the module from. |
| `-GitRelease`| `string` | URL to download a specific release asset (.zip/.tar.gz). |
| `-PackageId` | `string` | ID for Winget, Scoop, or Brew. |
| `-Arch` | `string[]` | Allowed architectures (`x64`, `arm64`, `any`). |
| `-OutputExported` | `switch` | Prints a summary of commands after the first load. |

#### `Get-LazyModule`
Lists all registered definitions.

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `-Name` | `string` | Unique identifier and command trigger name. | 


#### `Unregister-LazyModule`
Removes a module definition.

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `-Name` | `string` | Unique identifier and command trigger name. |

---

### **Example Output**

```powershell
PSLazy >  INF  [register] Initializing lazy module: Pester  source: Pester
PSLazy >  ACT  [git] Cloning 'Pester' from https://github.com/pester/Pester...
PSLazy >  SUC  [git] Cloned 'Pester' to ~/.local/share/powershell/PSLazy/Modules/Pester
PSLazy >  INF  [git] Checked out tag 'v5.5.0' for 'Pester'.
PSLazy >  INF  [git] Resolved entry point: .../Pester/Pester.psd1
PSLazy >  SUC  [register] Registered 'Pester' with 42 commands.

PSLazy >  INF  [register] Initializing lazy module: InternalTools  source: https://github.com/myorg/InternalTools
PSLazy >  ACT  [git] Pulling latest for 'InternalTools'...
PSLazy >  SUC  [git] Pulled latest 'InternalTools'.
```

---

### **License**

This project is licensed under the [MIT License](https://github.com/yourusername/pslazy/blob/main/LICENSE).