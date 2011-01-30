#!/bin/bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This script is used to compare the prices and passmark benchmarks of graphic cards for sale on kakaku.com in Japan.
# The script could easily be modified to work with newegg for example but would require some modifications by somebody who knows how to work bash.
# I've added some notes throughout to help you modify the script to your needs.
# (c) 2011 Joe Balough

# See if help was requested
if [ "$1" == "-h" -o "$1" == "--h" -o "$1" == "--help" ] 
then
  echo "$0 is a shell script that uses sed to parse the html pages returned by kakau.com"
  echo "and an Asus QVL list to build a MySQL database that contains all that information."
  echo "After all that, it queries the database to join the two sources of information to make selecting"
  echo "good compatible ram easier."
  echo "The query outputs to a file called ram_data.tsv in the current working directory."
  echo "This file is a tab-separated-value file that is easily imported into any spreadsheet program."
  echo ""
  echo "You must also have a mysql database configured called 'ram' that you have full privilages on."
  exit 1
fi

# Check for qvl
echo -n "Checking for ASUS QVL List: "
if [ -a "qvl.txt" ]
then
  echo "ok."
else
  echo "failed."
  echo "    This script needs a copy of the ASUS QVL list for your mainboard."
  echo "    Go to asus.com and search for your mainboard. Then go to \"Memory Support List\""
  echo "    and download the memory QVL list. Unzip it, then open it up in okular."
  echo "    Use okular's export feature to export it as a plain txt file and call it qvl.txt"
  exit 1
fi

# This will use sed to parse the qvl list.
# It matches on a very specific pattern and replaces the whole line with a simple one that has the format
#        1              2         3        4        5         6          7        8        9
#    Manufacturer    Part No.    Size    SS/DS    Timing    Voltage    1Dimm    2Dimm    4Dimm
# Where each item has a tab between it. This data can be easily loaded into mysql with the following command:
#    LOAD DATA LOCAL INFILE "qvl.tsv" INTO TABLE qvl;
# This command will probably not need to be modified.
# That last 'g' is needed to ensure it does all replacements. The last 'p' combines with the -n option to ONLY print the lines that have been changed ONCE.
# Example line:      A-DATA                        AD31600G001GMU                           1GB             SS             -                     -                       9-9-9-24           1.65~1.85       ●       ●
grep "^  \+.*  \+.*  \+[1-9]GB" qvl.txt | sed "s:^  \+::g" | sed "s:  \+:\t:g" | grep "^" > qvl.tsv

# Make sure there's some data in that file
ram_entries=`wc -l qvl.tsv | awk '{print($1)}'`
if [ $ram_entries -lt 50 ]
then
  echo "Warning: The processed QVL file gave fewer than 50 entries for the database."
  echo "         This may be because ASUS changed the layout the file and the sed regex doesn't work anymore."
  echo "         Got $ram_entries entries. Continuing anyway."
fi

exit 0

echo "Searching kakaku.com for RAM modules..."

# Loop through getting all the kakaku page listings
for (( i=1; i<=$ram_entries; i++ ))
do
  # Search url for kakaku.com
  #    http://kakaku.com/search_results/?c=&query=$card&category=&minPrice=&maxPrice=&sort=popular&rgb=&shop=&act=Input&l=l&rgbs=
  echo -n "  $Part No: "
  
done

# Clean up
rm qvl.tsv

exit 0