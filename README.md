![store](https://github.com/KeithGDR/sm-store/blob/master/logo.png "store")

## Description
An open store plugin for SourceMod. 

More documentation and tutorials can be found at [our wiki](https://github.com/KeithGDR/sm-store/wiki/wiki).

### Requirements

* SourceMod setup on a dedicated server for a Source Engine game that it supports.
* MySql or MariaDB server.

### Features

* **Modular** and **Extensible** - This package is organized in modules, where each module is a different SourceMod plugin. You can extend the store, [add new items](https://github.com/KeithGDR/sm-store/wiki/Creating-items-for-Store) or anything you can think of just by writing a new SourceMod plugins.
* Each item module uses JSON to parse through items and to let you store them on the database.
* The plugin has modules for the shop, inventory, loadouts, logging, refunds, gifting, credit distributions and more.
* The store system itself is compatible with every Sourcemod supported game out of the box. (Item modules do not though even though most of them do.)

### Modules
* **Backend** - Handles pretty much all of the MySql/MariaDB data storage and gives feedback to other plugins on player, category and item information.
* **Core** - Handles most of the main line plugin functionality like menus, credits and client initialization.
* **Distributor** - Handles credit distribution to client in a variety of different ways.
* **Gifting** - Handles players giving items and credits to each other.
* **Installer** - Handles the installation of all or different systems.
* **Inventory** - Handles players inventory and the ability to equip and unequip items.
* **Loadout** - Handles different loadouts of items for players to equip at different points in time.
* **Logging** - Handles all logging across the other modules.
* **Refund** - Handles all refunds players might want for certain items.
* **Shop** - Handles item purchases through credits in the system.

## Initial Installation

Just download the attached zip archive and extract to your sourcemod folder intact. Then navigate to your `configs/` directory and add the following entry in `databases.cfg`:
    
    "store"
    {
        "driver"        "mysql"
        "host"          "<your-database-host>"
        "database"		"<your-database-name>"
        "user"		    "<username>"
        "pass"		    "<password>"
    }

### Option A (Recommended)
Use the `sm_install` command in-game as root admin and go through the steps of installing the plugin from there.

### Option B (Not Recommended)
Then, navigate to `configs/store/sql-init-scripts` and execute `store.sql` in your database. For item modules you want to add, make sure the `.json` file is in the folder `/configs/store/json-import/` and execute the command `sm_installitems` in-game as root admin in order to install them.

After the installation is complete, delete the `store-installer` plugin from your server and restart it.

([Tutorial](https://github.com/KeithGDR/sm-store/wiki/Installing-Store))

## License

Copyright (C) 2013-2025  Alon Gubkin, Keith Warren

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
