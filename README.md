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
### Desktop
![Desktop](https://github.com/user-attachments/assets/e7583e95-e148-472e-9376-1eebe46a9da1)
### App Launcher
![Launcher](https://github.com/user-attachments/assets/6a97d889-7892-400b-8093-d938f90f34f0)
### Notifications
![Notifications](https://github.com/user-attachments/assets/5cf9bb8b-343b-4001-abf1-c26c66e7586e)
### Calendar
![Calendar](https://github.com/user-attachments/assets/dd4eb5bf-74bd-4824-8add-583c5684ef98)
### Shutdown Menu
![Shutdown](https://github.com/user-attachments/assets/a55a1558-49a6-4b8a-a70b-23667b4c74fc)
### Task Switcher
![Switcher](https://github.com/user-attachments/assets/e61f5611-2d8f-4bf5-babe-7652bf8f30d5)

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
