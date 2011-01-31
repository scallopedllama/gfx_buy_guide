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

echo "Checking RAM Modules..."

# Loop through getting all the kakaku page listings
for (( i=1; i<=$ram_entries; i++ ))
do
	# Get ram module part no to search for
	part_no_unmodified=$(sed -n "$i p" qvl.tsv| awk -v FS="\t" '{print($2)}')
	part_no=$(echo "$part_no_unmodified" | sed "s:(.*)::g" | sed "s:Ver.\..::g" | sed "s:\..*::g" | sed "s:/:%2F:g" | sed "s: ::g" )
	
  echo "  Part No: $part_no"
  echo -n "    Searching Kakaku.com: "
  
  # Search url for kakaku.com
  #    http://kakaku.com/search_results/?c=&query=$card&category=&minPrice=&maxPrice=&sort=popular&rgb=&shop=&act=Input&l=l&rgbs=
  wget -q -O kakaku_search.sj.html "http://kakaku.com/search_results/?c=&query=$part_no&category=&minPrice=&maxPrice=&sort=popular&rgb=&shop=&act=Input&l=l&rgbs="
  iconv -c -s -f SHIFT_JIS -t UTF-8 kakaku_search.sj.html > kakaku_search.html
  rm kakaku_search.sj.html
  
  # See if there was a result and report that to user
  no_results=$(grep -c "<span class=\"price\">" kakaku_search.html)
  if [ $no_results == 0 ]
  then
    echo "no results."
    continue
  else
		echo -n "$no_results result."
  fi
  if [ $no_results -gt 1 ]
  then
    echo "Note: $part_no returns $no_results results. Only using first result."
  fi
  
  # Since there was a result, get the first price and product url from the page
  price=$(sed -n 's:^.*<span class="price">&yen;\([0-9]*\),*\([0-9]*\) 〜 </span>.*$:\1\2:p' kakaku_search.html)
  product_url=$(sed -n "s:^.*<a class=\"title\" \+href=\"\(.*\)\">.*$:\1:p" kakaku_search.html)
  echo " Price: $price"
  # and dump it out to a tsv file
  echo -e "$part_no_unmodified\t$price\t$product_url" >> kakaku_results.tsv
  
  rm kakaku_search.html
  
  # Done with kakaku search
  
  echo -n "    Searching Newegg.com: "
  
  # Newegg search url: http://www.newegg.com/Product/ProductList.aspx?Submit=ENE&DEPA=0&Order=BESTMATCH&Description=$part_no
  # This can either return a product page, a search with no results, or a search with more than one result
  newegg_search_url="http://www.newegg.com/Product/ProductList.aspx?Submit=ENE&DEPA=0&Order=BESTMATCH&Description=$part_no"
  wget -q -O newegg_search.html $newegg_search_url
  
  if [ $(grep -c "<h2>Search Tips</h2>" newegg_search.html) -gt 0 ]
  then
    echo "no results."
    continue
  fi
  
  rating=""
  newegg_url=""
  if [ $(grep -c "<dd>Item#" newegg_search.html) -gt 0 ]
  then
    rating=$(sed -n "s:.*<img class=\"eggs r[0-9] screen\" title=\"\([0-9]\) out of 5 eggs\".*:\1:p" newegg_search.html)
    newegg_url="$newegg_search_url"
  else
		# This sed command gets the top result and gets its rating and the url of the review for that product.
		rating=$(sed -n "s:<a title=\"Rating + \([0-9]\)\" href=\"\(.*\)\" class=\"itemRating\"><span class=\"eggs r3\">&nbsp;</span> (9)</a>:\1:p" newegg_search.html)
		newegg_url=$(sed -n "s:<a title=\"Rating + \([0-9]\)\" href=\"\(.*\)\" class=\"itemRating\"><span class=\"eggs r3\">&nbsp;</span> (9)</a>:\2:p" newegg_search.html)
  fi
  echo "found with rating of $rating eggs."
  echo -e "$part_no_unmodified\t$rating\t$newegg_url" >> newegg_results.tsv
  
  rm newegg_search.html
  
done

# Clean up
#rm qvl.tsv
#rm kakaku_results.tsv
#rm newegg_results.tsv

exit 0