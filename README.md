<img width="80" height="80" alt="Logo-iOS-Default-1024x1024@1x" src="https://github.com/user-attachments/assets/0efef770-6c63-4f4c-93de-881f6cd68443" />

# Procyon

A Steam game launcher for macOS that can run both Windows and MacOS Games.
It's based on Crossover so you will need to download and install Crossover first

- Replaces CXPatcher, will patch your copy of crossover and add a nice interface to launch steam games
- You can configure the graphics backend and the vulcan backed along with advanced options for every game
- **It can run 32bit games much faster thanks to x87 via rosettaX87**
- You can run doom 2016 using moltenvk - experimental
- You can run UE4 games via dxvk using the ue4 hack (enabled by default)

This is still a work in progress, use at your own risk, I'll provide more instructions later but for starters, all you have to do is select a crossover app and a bottle and the rest will be auto-configured

![Screenshot 2026-03-19 at 22 50 46](https://github.com/user-attachments/assets/6ed53e07-5a66-4ada-90d6-f6134e7a275b)

- The library will list all of your owned games and installed games both on mac and on wine
- There are per-game launch options
-  You can see the options and the detail page by clicking on each thumbnail (see image below)
- The profile page is very rudimentary, I just started working on it

![Screenshot 2026-03-19 at 22 51 13](https://github.com/user-attachments/assets/ec5ef2ad-b15c-4971-8673-68c9eec83beb)

![Screenshot 2026-03-19 at 22 52 03](https://github.com/user-attachments/assets/a545beda-814c-4bb7-a042-4b85c0322f34)

I wrote a to do list here:
https://github.com/italomandara/Procyon/issues/1

Which is pretty much in line with the roadmap

Thanks to: 
@Lifeisawful https://github.com/Lifeisawful for rosettax87
@Gcenx https://github.com/Gcenx for wine patched components and dxvk-macos
@nastys https://github.com/nastys for the UE4 Moltenvk hack
https://www.codeweavers.com for Crossover
