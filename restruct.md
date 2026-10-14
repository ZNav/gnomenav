```RESET of Gnomenav.com```
.  /\
. (oo)
.{.vv.}

needed outcomes
under 5 min downtime on reset and reboot
multiple flakes for each item rather than docker all virtualized {
  jellyfin
  photo host
  nextcloud
  kavita
  navidrome
  minecraft server
  
behind mullvad wireguard{
  qbit
  all arr -> nextcloud + media
  }
}

what to use as hypervisor?
should the sandisk ssd be used for RW actively like RAID or will it degrade too quickly?

purchase router that suits homelab goals, bonus points for rack or LORA + meshtastic integration
purchase 8U 10" mini rack
purchase mini switch and lan cables
purchase cd rw for in rack

software {
  music playlist maker for easy navidrome selection of items and folder creation script for mp3 player onboard with auto-usb trust for certain names and autowrite once on
  tailscale and or finish cloudflare ssh tunnel for turning on when off-site
  new homepage
}

hardware {
  msi 15 delta Ryzen7 with GPU and 16gb ram 1tb ssd
  thinkpad yoga intel i5 probably 2gb ram 500gb hard drive
  x220 1tb hard drive 8gb ram (i think)
}

porting - - - - - ->

gnomenav
project outlines
entirely reproduceable via SFC + secrets / .env
easily make others willing (or ideally unwilling participants) in the network without leaving behind PII
5-10 min restart -> uptime
easy to maintain, explain and understand + troubleshoot
multiple isolated vms / worker nodes / services?
better file management and layout -> easier long term reproducible system+
needless and utter control over everything, to about 80% of reasonability
easy deployment pipeline + build in public (where feasible)
very quick plug and play into things while having maximum control + access 
current software
movies + shows : jellyfin (is plex or another fork better?)
books + comics : kavita
files / drive : nextcloud
music : navidrome

vpn-isolated : mullvad {
    qbit (build in better storing of items from default {
         prowlarr {
             radarr : movies
             sonarr : shows}}}

integrate {
    some form of email self hosted / communication
    HTB ez deploy multitool partially persistant
    minecraft server
    some really powerful arr indexer / grabber
    SSO
    lifelongDB (nosql?)
    navTUI -> ghomeOS (home level dashboard customized with launchers to all services and easy SSO along with easy admin controls + dashboards)
    immich for photos
    custom ez playlist either import from spotify/yt OR via another means -> playlist saved on db -> linked to stored file available and starts search for missing -> easy webUI for plug and play write onto mp3 player as playlist or burn CD}

questions {
    do we need pacman?
    do we need docker?
    do we need k3 +xor k8? (incus??)
    transcoding / load management}}

hardware {
    msi15delta(ryzen7, 1tb ssd, gpu) 
    x220 (usbc, intel i7, 1tb hard drive)
    x220 (!=battery, intel i7
    thinkpad yoga(500gb hard drive)}

plans:
sfc config.nix + .env for everything, manual manual manual to start, min services.
    
