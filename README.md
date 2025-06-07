<p align="center"><img src="https://imgur.com/qZz4J5l.png" width=250></p>

A lightweight tiling window manager with modern creature comforts and style, built on Awesome WM.

## Features
- Tiling window management- no more jumbled windows!
- Robust application launcher with the ability to pin apps for quick access and run with sudo
- Notification tray that stores notifications you might have missed
- System tray for background tasks
- Interactive calendar
- Shutdown menu
- Task swither (like Alt+Tab from Windows)
- Ultrawide monitor support: splits displays wider than 16:9 into two "logical screens"
- Configuration & theme variables

## Screenshots
![1739296819](https://github.com/user-attachments/assets/50e0d746-9b7b-484c-b7ec-79c321d28401)
![1739296876](https://github.com/user-attachments/assets/d23008d9-dbbf-473a-8d10-67e619859660)
![1739296748](https://github.com/user-attachments/assets/738555ca-d4a7-4653-8878-eb23e31c71fa)
![1739297706](https://github.com/user-attachments/assets/07cec3ff-bf34-4d26-b7e2-ccba5255f778)
![1739298031](https://github.com/user-attachments/assets/34b56c59-65e9-4a30-b88c-3ab9c2044785)
![1739383800](https://github.com/user-attachments/assets/471bc257-1289-4948-ba78-e43004f06127)

## Required Extras
List of required external programs for MoMoS to run properly:
- **Zenity**: Simple API for creating dialog GUIs. Used for running programs with sudo in the application launcher
- **PlayerCTL**: Universal music player API. Music controls will not work without it

## Recommended Extras
A list of additional applications for the best experience:
- **Picom** (Jonaburg Build): Lightweight compositor that adds transparency and animation effects
    - You will have to build it yourself, but it's pretty easy: https://github.com/jonaburg/picom
    - The "extras" folder contains a good default config, which you can put into ~/.config/picom/

## Setup
- Copy all of the files in this repository (except the "extras" folder) into your AwesomeWM config directory (~/.config/awesome/)
- Configure your desired settings in the config.lua file (especially the "Default Applications" section)
- Restart Awesome WM
- **You're good to go!**

*Note: Awesome WM needs to be restarted after making config changes. The MoMoS hotkey for this is **Ctrl+Mod+R***.
