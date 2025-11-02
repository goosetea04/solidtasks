# solidtasks

**solidtasks** is a Flutter-based task management app that leverages decentralized data storage and fine-grained access control using [Solid Pods](https://solidproject.org/). This project empowers users to securely create, store, and share tasks while maintaining full ownership and privacy over their data.

## Features

* **Decentralized Storage:** All user tasks are stored in the user's own Solid Pod, not on a centralized server.
* **Fine-Grained Access Control:** Share tasks with specific individuals or groups using Solid's flexible access control features.
* **Cross-Platform:** Runs on Android, iOS, Web, and Desktop via Flutter.
* **Open Source:** Licensed under the GNU General Public License (GPL).

## Getting Started

### Prerequisites

* [Flutter](https://docs.flutter.dev/get-started/install) (Stable Channel)
* A registered [Solid Pod](https://solidproject.org/users/get-a-pod)
 
### Installation

1. **Create a pod with a server that supports ACP specifications**
   
   For purposes of development and testing we are using [Solidcommunity.au ACP](https://pods.acp.solidcommunity.au). Create an account (WebID) with that solid server provider. 

2. **Clone the repository:**
```bash
   git clone https://github.com/yourusername/solidtasks.git
   cd solidtasks
```

3. **Install dependencies:**
```bash
   flutter pub get
```

4. **Run the app:**
```bash
   flutter run
```

5. **Login with your Solid Pod:**

   * Upon launching the app, sign in using your Solid Pod credentials. 
   * **Important:** The solid pod server you are logging into must support the ACP specification. For development and testing, we recommend using [Solidcommunity.au ACP](https://pods.acp.solidcommunity.au).

6. **Handle Access Control Files (Known Issue):**

   [Solidcommunity.au ACP](https://pods.acp.solidcommunity.au) currently has a known issue where it creates `.acl` files instead of `.acr` (Access Control Resource) files when using the ACP specification. 
   
   **Workaround:**
   * After creating your first tasks, check your Pod storage for any `.acl` files
   * Manually rename these files to `.acr` files
   * Update any references in your task metadata to point to the `.acr` files instead
   * This issue should be resolved in future updates to the Solid server implementation

### Troubleshooting

* **Authentication Issues:** Ensure your Pod provider supports the ACP specification
* **Access Control Errors:** Verify that `.acr` files are being used instead of `.acl` files
* **Connection Problems:** Check your internet connection and Pod server status

## Contributing

We welcome contributions! Please fork the repository and submit a pull request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

## Resources

* [Solid Project Documentation](https://solidproject.org/)
* [Flutter Documentation](https://docs.flutter.dev/)
