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
  echo "You must also have a mysql database configured called 'guide' that you have full privilages on."
  exit 1
fi

# Check for qvl
echo -n "Checking for ASUS QVL List: "
if [ -a "qvl.pdf" ]
then
  echo "ok."
else
  echo "failed."
  echo "    This script needs a copy of the ASUS QVL list for your mainboard."
  echo "    Go to asus.com and search for your mainboard. Then go to \"Memory Support List\""
  echo "    and download the memory QVL list. Unzip it, and rename the file to qvl.pdf"
  exit 1
fi

# Convert the qvl
echo -n "Converting QVL List to text: "
type -P pdftotext &>/dev/null || {
  echo "failed."
  echo "    This script requires the pdftotext utility to be installed."
  echo "    Aborting." >&2;
  exit 1;
}
pdftotext -layout qvl.pdf qvl.txt
echo "ok."

# This will use sed to clean up the qvl list.
# It starts by removing empty lines and then puts a '-' in all empty dimm fields
sed '/^$/d' qvl.txt | sed 's/^\(.\{190\}\) /\1-/' | sed 's/^\(.\{199\}\) /\1-/' | sed "s:^  \+::g" | sed "s:  \+:,:g" > qvl.p.ssv

echo -n "Adding Ram Speeds to list: "
for (( i=1; i<=`wc -l qvl.p.ssv | awk '{print($1)}'`; i++ ))
do
	line=$(sed -n "$i p" qvl.p.ssv)
	
	# See if this is the start of a new speed section
	if [ `echo $line | grep -c "^DDR3 [0-9]* Qualified Vendors List (QVL)$"` -gt 0 ]
	then
	  speed=$(echo $line | sed 's/^DDR3 \([0-9]*\) Qualified Vendors List (QVL)$/\1/')
	  continue
	fi
	
	# Must not be, see if it's an entry
	if [ `echo $line | grep -c "^.*,.*,[0-9]GB"` -gt 0 ]
	then
	  echo -e "$speed,$line" >> qvl.ssv
	fi
done

# Remove all groups of spaces longer than 2 spaces long, replace those double spaces with tabs
sed "s:,:\t:g" qvl.ssv > qvl.tsv
rm qvl.ssv
rm qvl.p.ssv

echo "ok."


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
	part_no_unmodified=$(sed -n "$i p" qvl.tsv| awk -v FS="\t" '{print($3)}')
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
    rm kakaku_search.html
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
  no_reviews=""
  if [ $(grep -c "<dd>Item#" newegg_search.html) -gt 0 ]
  then
    rating=$(sed -n "s:.*<img class=\"eggs r[0-9] screen\" title=\"\([0-9]\) out of 5 eggs\".*:\1:p" newegg_search.html)
    newegg_url="$newegg_search_url"
    no_reviews=$(sed -n "s:.*\"display\:none;\">[0-9]/5</span>(\([0-9]*\)&nbsp;reviews)</a>.*:\1:p" newegg_search.html)
  else
		# This sed command gets the top result and gets its rating and the url of the review for that product.
		rating=$(grep -m 1 "<a title=\"Rating +" newegg_search.html | sed -n "s:.*<a title=\"Rating + \([0-9]\)\" href=\".*\" class=\"itemRating\"><span class=\"eggs r[0-9]\">&nbsp;</span>.*:\1:p")
		newegg_url=$(grep -m 1 "<a title=\"Rating +" newegg_search.html | sed -n "s:.*<a title=\"Rating + [0-9]\" href=\"\(.*\)\" class=\"itemRating\"><span class=\"eggs r[0-9]\">&nbsp;</span>.*:\1:p")
		no_reviews=$(grep -m 1 "class=\"itemRating\">" newegg_search.html | sed -n "s:.*class=\"itemRating\"><span class=\"eggs r[0-9]\">&nbsp;</span> (\([0-9]*\))</a>.*:\1:p")
  fi
  echo "found with rating of $rating eggs after $no_reviews reviews."
  echo -e "$part_no_unmodified\t$rating\t$no_reviews\t$newegg_url" >> newegg_results.tsv
  
  rm newegg_search.html
  
done

qvl_entries=`wc -l qvl.tsv | awk '{print($1)}'`
kakaku_entries=`wc -l kakaku_results.tsv | awk '{print($1)}'`
newegg_entries=`wc -l newegg_results.tsv | awk '{print($1)}'`

echo ""
echo "Finished Searching for $qvl_entries products from the RAM QVL."
echo "Found $kakaku_entries entries available at Kakaku.com with $newegg_entries entries also found at Newegg."

# Now on to the mysql business
# Get the mySql password and username
read -p "Please enter MySQL Username: " username
stty -echo
read -p "Please enter MySQL Password: " password; echo
stty echo

# Now run the relevant commands.
echo ""
echo -n "Dropping old tables..."
mysql -u$username -p$password -e "USE guide; 
	DROP TABLE kakaku_ram; DROP TABLE newegg_ram; DROP TABLE qvl_ram;" > /dev/null 2>&1
echo "ok"
echo -n "Re-creating old table..."
mysql -u$username -p$password -e "USE guide;
	CREATE TABLE kakaku_ram (part VARCHAR(256), price INT(11), url VARCHAR(256));
	CREATE TABLE newegg_ram (part VARCHAR(256), rating INT(2), reviews INT(11), url VARCHAR(256));
	CREATE TABLE qvl_ram (speed INT(11), maker VARCHAR(128), part VARCHAR(256), size VARCHAR(56), sidedness VARCHAR(2), chip_brand VARCHAR(128), chip_no VARCHAR(256), timing VARCHAR(256), voltage VARCHAR(256), dimm_1 CHAR(1) DEFAULT \"F\", dimm_2 CHAR(1) DEFAULT \"F\", dimm_4 CHAR(1) DEFAULT \"F\");"
echo "ok"
echo -n "Adding data..."
mysql -u$username -p$password -e "USE guide;
	LOAD DATA LOCAL INFILE \"qvl.tsv\" INTO TABLE qvl_ram;
	LOAD DATA LOCAL INFILE \"kakaku_results.tsv\" INTO TABLE kakaku_ram;
	LOAD DATA LOCAL INFILE \"newegg_results.tsv\" INTO TABLE newegg_ram;"
echo "ok"
echo -n "Running query..."
mysql -u$username -p$password -e "USE guide;
  SELECT q.maker, q.part, q.size, q.speed, k.price, n.rating, n.reviews, q.dimm_1, q.dimm_2, q.dimm_4, k.url, n.url FROM qvl_ram q RIGHT JOIN kakaku_ram k ON q.part=k.part INNER JOIN newegg_ram n ON k.part=n.part ORDER BY k.price ASC;" > ram_data.tsv
echo "ok"

echo ""
echo "All done."
echo "The joined data has been dumped into the file called ram_data.tsv."
echo "It's a tab-separated-value file that can easily be pasted into a spreadsheet to get a better look at the data."
echo "All intermediate files including the original html data has been deleted. The MySQL database tables remain."

# Clean up
rm qvl.tsv
rm kakaku_results.tsv
rm newegg_results.tsv

exit 0