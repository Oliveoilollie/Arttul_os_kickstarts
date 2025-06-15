# ArttulOS

![ArttulOS Logo](https://github.com/Sprunglesonthehub/arttulos-assets/blob/main/A.png)

**A stable, user-friendly Linux distribution based on Rocky Linux, designed for everyone.**

---

### Welcome to ArttulOS

ArttulOS is a community-driven project that takes the rock-solid foundation of **Rocky Linux** and enhances it for newcomers and users who demand a stable, reliable desktop experience. Our goal is to provide an operating system that just works, allowing you to focus on your tasks without worrying about system failures or complex configurations.

### Key Features

*   **Rock-Solid Stability**: Built upon the enterprise-grade foundation of Rocky Linux.
*   **User-Friendly**: A curated selection of software and a polished desktop environment make it easy for anyone to get started.
*   **For Everyone**: Whether you're a student, a developer, or just someone tired of system updates breaking your workflow, ArttulOS is for you.
*   **Flexible Installation**: Build the perfect image for your needs, from fully interactive setups to completely automated deployments.

---

## Building Your ArttulOS Image: Installation Modes

> **Note:** The features and build script described below are located in the **`natalie`** branch of this repository.

To build an ArttulOS image, use the `iso_builder.sh` script located in the `scripts/` directory. You can apply flags to this script to select the desired installation mode.

### 1. Default Mode (Interactive Installation)

This is the standard, non-automated experience. The user will be guided through the familiar Anaconda installer to partition their disks, create a user account, and configure their system manually.

**When to use it:** For personal installations on your own machine where you want full control over the setup process.

**How to build:**
```bash
sudo ./scripts/iso_builder.sh
```
*(Running the script with no flags defaults to this mode.)*

---

### 2. OEM Mode (`--oem`)

The OEM mode provides a **completely automated, hands-off installation experience**. The system installs itself without requiring any user input during the process.

On the very first boot, the *end-user* is presented with a setup wizard to create their own user account, set their language, and configure their timezone.

**When to use it:** Ideal for hardware vendors, IT departments, or anyone pre-installing ArttulOS on a computer for another person. It gives the final user a fresh, "out-of-the-box" setup experience.

**How to build:**
```bash
sudo ./scripts/iso_builder.sh --oem
```

---

### 3. Appliance Mode (`--appliance`)

The Appliance mode creates a **generic, pre-configured image**. The installation is automated, and the system is ready to use immediately upon first boot with a default user account already created.

**When to use it:** Perfect for virtual machines, testing environments, kiosks, or any scenario where a standardized, non-personalized setup is required. Just boot it up and log in.

**Login Credentials:**
*   **Username:** `arttulos`
*   **Password:** `arttulos`

**How to build:**
```bash
sudo ./scripts/iso_builder.sh --appliance
```

---

## Getting Started

Ready to build your first ArttulOS image? Follow these steps.

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/Oliveoilollie/Arttul_os_kickstarts.git
    cd Arttul_os_kickstarts
    ```

2.  **Switch to the `natalie` Branch:**
    ```bash
    git checkout natalie
    ```

3.  **Install Dependencies:**
    *( `sudo dnf install ...`)*

4.  **Run the Build Script:**
    Choose your desired mode and run the script from the root of the project directory. For example, to build an appliance image:
    ```bash
    sudo ./scripts/iso_builder.sh --appliance
    ```

## Contributing

ArttulOS is a community project, and we welcome contributions of all kinds! Whether you're a developer, a designer, a tester, or a documenter, we'd love to have you.

## Acknowledgements

A huge thank you to the **Rocky Linux Project** and its community for providing the incredibly stable and secure base that makes ArttulOS possible.

## License

This project is licensed under the AGPL License - see the [LICENSE](LICENSE) file for details.
