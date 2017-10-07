Bonjeff is a Mac app that shows you a live display of the Bonjour services published on your network. Bonjeff is intended as a replacement for the discontinued Bonjour Browser app by Kevin Ballard. Bonjour Browser predated Gatekeeper and thus is not code signed with a Developer ID certificate. Bonjeff is validly code signed, which allows it to be installed on Macs protected by Gatekeeper.

Build Instructions:
The Bonjeff Xcode project is configured to code sign the app. For code signing, you need a valid Mac Developer code signing certificate in your keychain, and you need to specify your Apple Developer Program TeamID in the build settings. Create a new file "DEVELOPMENT_TEAM.xcconfig" in your working copy and add the following build setting to the file:

DEVELOPMENT_TEAM = [Your TeamID]

The "DEVELOPMENT_TEAM.xcconfig" file should not be added to any git commit. The ".gitignore" file will prevent it from getting committed to the repository.

See the LICENSE.txt file for the Bonjeff software license agreement.

Bonjeff is Copyright © 2017 Jeff Johnson. All rights reserved.
