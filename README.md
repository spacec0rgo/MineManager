# MineManager
I developed this script to easily manage Minecraft servers in Linux environments in my homelab.

Since it works quite good and served me well during the early stages of development, I decided to make it open source so that others can enjoy it too.

## Options
Here is a quick help page. I might improve the README in the future.
```
MineManager is a bash wrapper developed to manage Minecract servers
This tool is used to start/stop the server, update the server.jar file, 
send admin commands, check on server status and clear server logs

Made with love by c0rgo (https://github.com/spacec0rgo)

Usage:
        ./minemg.sh [flags] ...
    
Flags:
        -h, --help				            print this help page
        --start					            start the MC server
        --stop					            stop the MC server
        -c, --command <command>		        send quote-enclosed command [eg. 'say Hello'] to the MC server
        -up, --update				        update server.jar file if a new release is available
        --status				            check MC server status
        -vv, --versions <num|all>	        retrieve number of MC server versions available to install
        -iv, --install-version <version>	install a specific server release version
        -sku, --skip-up-check			    skip automatic check for new releases
        -fd, --force-download			    force download server.jar even if versions match
        -bak, --backup <path>			    create a backup of the MC server world
        -cls, --clean-logs			        remove old logs from the Java logs directory
```