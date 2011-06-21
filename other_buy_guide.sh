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
  echo "Usage: $0 [number of kakaku pages to parse]";
  echo "    $0 is a shell script that uses sed to parse the html pages returned by kakaku.com"
  echo "    and newegg.com to build a MySQL database that contains all that information."
  echo "    After all that, it queries the database to join the two sources of information to make selecting"
  echo "    a good part easier."
  echo "    The query outputs to a file called part_data.tsv in the current working directory."
  echo "    This file is a tab-separated-value file that is easily imported into any spreadsheet program."
  echo ""
  echo "    Note that the input is not checked for validity."
  echo "    You must also have a mysql database configured called 'guide' that you have full privilages on."
  exit 1
fi


echo "Getting kakaku.com page listings."

# Loop through getting all the kakaku page listings
for (( i=1; i<=$1; i++ ))
do
  # All the pages of the kakaku listings      \/ Page number, ex: 001, 002, etc
  #    http://kakaku.com/pc/power-supply/ma_0/r2NNN/s1=700-900/
  echo -n "  Page $i: "

  # To modify this to work with a different source like Newegg, you need to go to that page and
  # filter the list down as much as possible. For example, the kakaku page above returns only PCI Express 16x
  # cards with 1GB or more of RAM. If you only want to look at Nvidia cards, include that in the filter.
  # Once you have the list filtered to your liking, copy out the url of the first page of results into a text editor.
  # Then go to the second page of results and copy that url into the same text editor.
  # Try to find what changes in the url between each page of the results.
  # For the kakaku example, the .../p1001/... part of the url changes to .../p1002/... for the second page.
  # If the url of your results page increments by some arbitrary amount every page, you will need to modify
  # the for loop on line 60 to the following:
  # for (( i=$start_value; i<=$(($1*$arbitrary_amount+$start_value)); i+=$arbitrary_amount ))
  # Where $arbitrary_amount is how much each page increments by and $start_value is where it starts.

  # This formats the current page counter to a string with 0s padding the front so that it is 2 characters long.
  # If the number of pages in your results go into the hundreds or thousands, you will need to modify the amount
  # padding this printf uses.
  j=$(printf "%02d" "$i")

  # The text after the -O flag indicates the output so don't change that, just change the url that follows.
  # Take the url you got from your search and put it here and replace only the part that changes with a $j.
  # It should work just fine so long as you changed the printf above correctly.

  # Search for power supplies
  wget -q -O search.p$j.sj.html http://kakaku.com/pc/power-supply/ma_0/r20$j/s1=700-900//
  # Search for hard drives
  #wget -q -O search.p$j.sj.html http://kakaku.com/pc/hdd-35inch/ma_0/e20$j/s1=1000/s3=1/

  # Make sure it's there
  if [ -a "search.p$j.sj.html" ]
  then
    echo "ok."
  else
    echo "failed."
    echo "    There was a problem getting the kakaku.com page listings."
    echo "    Check the url in the script and try again."
    exit 1
  fi

  # Kakaku.com uses the Shift_JIS encoding for all their pages. That needs to be converted to UTF-8
  # Or sed WILL fail to match Japanese characters with the . wildcard.
  # If you're working on a US site, you can remove these two lines. If it's some other international site,
  # you will probably have to change the from encoding after the -f tag.
  iconv -f SHIFT_JIS -t UTF-8 search.p$j.sj.html > search.p$j.html
  rm search.p$j.sj.html
done


# This will use sed to parse the relevant data out of each of the html files for the kakaku listings.
# If you've never used sed before, it's probably a good idea to go look at a tutorial but here is the jist of what we're doing.
# Get an example line that contains ONE listing from the results page.
# Kakaku.com example line: "...<td class="item">Corsair<p><a href="http://kakaku.com/item/K0000045190/"><strong>CMPSU-850HX</strong></a></p></td><td class="td-price"><a href="http://kakaku.com/item/K0000045190/">&#165;15,999</a><br><span>アクロス</span></td><td>25店舗</td><td>22位</td><td>31位</td><td class="select">4.74<br><a href="http://review.kakaku.com/review/K0000045190/">(17件)</a></td><td><a href="http://bbs.kakaku.com/bbs/K0000045190/">131件</a></td><td>-</td><td>09/07/07</td><td>850W&nbsp;</td><td>ATX/EPS&nbsp;</td><td>150x180x86mm&nbsp;</td><td class="end">&yen;18.82&nbsp;</td></tr>"

for (( i=1; i<=$1; i++ ))
do
  j=$(printf "%02d" "$i")
  # Parsing for Power Supplies
  # 1: manufacturer, 2: url, 3: model, 4: price1, 5: price2, 6: Power rating, 7: size
  # Kak     "...<td class="item">Corsair <p><a href="   URL  "><strong>CM..HX</strong></a></p></td><td class=\"td-price\"><a href=..>&#165; Price1   , price2    </a><br><span>..</span></td><td>..</td><td>..</td><td>..</td><td class=\"select\">.*<br><a href=..>.*</a></td><td><a href=..>..</a></td><td>..</td><td>..</td><td>  PWR &nbsp;</td><td> SIZE &nbsp;</td><td>..</td><td class="end">..</td></tr>"
  sed -n "s:^.*<td class=\"item\">\(.*\)<p><a href=\"\(.*\)\"><strong>\(.*\)</strong></a></p></td><td class=\"td-price\"><a href=.*>&#165;\([0-9]*\),*\([0-9]*\)</a><br><span>.*</span></td><td>.*</td><td>.*</td><td>.*</td><td class=\"select\">.*<br><a href=.*>.*</a></td><td><a href=.*>.*</a></td><td>.*</td><td>.*</td><td>\(.*\)&nbsp;</td><td>\(.*\)&nbsp;</td><td>.*</td><td class=\"end\">.*</td></tr>:\1\t\3\t\4\5\t\6\t\7\t\t\2:gp" search.p$j.html >> kakaku.tsv

  # Parsing for Hard Drives
  # 1: Manufacturer, 2: url, 3: model, 4: price1, 5: price2, 6: size, 7: speed, 8 cache size
  #            <td class="item">  MGFR  <p><a href=\"  URL \"><strong> MODEL</strong></a></p></td><td class=\"td-price\"><a href=.*>&#165;  PRICE1  ,  PRICE2   </a><br><span>.*</span></td><td>.*</td><td>.*</td><td>.*</td><td>.*<br><a href=.*>.*</a></td><td><a href=.*>.*</a></td><td>.*</td><td class=\"select\">.*</td><td> SIZE &nbsp;</td><td> SPEED&nbsp;</td><td>CACHE &nbsp;</td><td>.*&nbsp;</td><td class=\"end\">.*</td></tr>
  #sed -n "s:^.*<td class=\"item\">\(.*\)<p><a href=\"\(.*\)\"><strong>\(.*\)</strong></a></p></td><td class=\"td-price\"><a href=.*>&#165;\([0-9]*\),*\([0-9]*\)</a><br><span>.*</span></td><td>.*</td><td>.*</td><td>.*</td><td>.*<br><a href=.*>.*</a></td><td><a href=.*>.*</a></td><td>.*</td><td class=\"select\">.*</td><td>\(.*\)&nbsp;</td><td>\(.*\)&nbsp;</td><td>\(.*\)&nbsp;</td><td>.*&nbsp;</td><td class=\"end\">.*</td></tr>:\1\t\3\t\4\5\t\6\t\7\t\8\t\2:gp" search.p$j.html >> kakaku.tsv
done

# make sure it has a reasonable number of entries
search_entries=`wc -l kakaku.tsv | awk '{print($1)}'`
one_less_pages=$(($1-1))
if [ $search_entries -lt $(($one_less_pages*40)) ]
then
  echo "Warning: The processed cards files gave fewer than 40 * ($1 pages - 1) entries."
  echo "         This may be because kakaku.com changed their site layout and the sed regex doesn't work anymore."
  echo "         Got $search_entries entries. Continuing anyway."
else
  echo "Got $search_entries search results."
fi

# Loop through checking each result
for (( i=1; i<=$search_entries; i++ ))
do
  part_no_unmodified=$(sed -n "$i p" kakaku.tsv| awk -v FS="\t" '{print($2)}')

  # Part number modifications for PSU
  # The part number we want to search for on newegg is the LAST word in the string that contains a '-' character.
  # Some parts have somthing like INFINITI-JC in the first word and EIN720AWT-JC in the second.
  # First we get the last word with a - in it, Account for the possibility that the first word had the -, then remove preceeding words if the last one is 4 or more characters, remove any /whatever from the end, and any (whatever) from the end
  part_no=$(echo "$part_no_unmodified" | sed "s:.* \([^ ]*-[^ ]*\) *[^-]*$:\1:" | sed "s:^\([^ ]*-[^ ]*\) .*$:\1:" | sed "s:^[^-]* \([^ ][^ ][^ ][^ W][^ ]*\)$:\1:" | sed "s:^\(.*\)/.*$:\1:" | sed "s:^\(.*\)(.*)$:\1:")

  # Part number modifications for HDD
  # The part number we want is always just the first word here with any /junk or (junk) removed
  #part_no=$(echo "$part_no_unmodified" | sed "s:\([^ ]*\) .*:\1:" | sed "s:^\(.*\)/.*$:\1:" | sed "s:^\(.*\)(.*)$:\1:")

  echo -n "  Searching for $part_no on Newegg.com: "

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


# Get the mySql password and username
read -p "Please enter MySQL Username: " username
stty -echo
read -p "Please enter MySQL Password: " password; echo
stty echo

# Now run the relevant commands.
echo ""
echo -n "Dropping old tables..."
mysql -u$username -p$password -e "USE guide;
  DROP TABLE kakaku_search; DROP TABLE newegg_search;" > /dev/null 2>&1
echo "ok"
echo -n "Re-creating old table..."
# kakaku.tsv: Manufacturer, model, price, size, speed, cache size, url
# newegg.tsv: model    rating    reviews    url
mysql -u$username -p$password -e "USE guide;
  CREATE TABLE kakaku_search (manufacturer VARCHAR(256), model VARCHAR(256), price INT(11), attrib_1 VARCHAR(126), attrib_2 VARCHAR(126), attrib_3 VARCHAR(126), url VARCHAR(256));
  CREATE TABLE newegg_search (model VARCHAR(256), rating INT(2), reviews INT(11), url VARCHAR(256));"
echo "ok"
echo -n "Adding data..."
mysql -u$username -p$password -e "USE guide;
  LOAD DATA LOCAL INFILE \"kakaku.tsv\" INTO TABLE kakaku_search;
  LOAD DATA LOCAL INFILE \"newegg_results.tsv\" INTO TABLE newegg_search;"
echo "ok"
echo -n "Running query..."
mysql -u$username -p$password -e "USE guide;
  SELECT DISTINCT k.manufacturer, k.model, k.price, n.rating, n.reviews, k.attrib_1, k.attrib_2, k.attrib_3, k.url AS kakaku_url, n.url AS newegg_url
  FROM kakaku_search k
  LEFT JOIN newegg_search n
  ON k.model=n.model
  ORDER BY k.price ASC;" > search_data.n.tsv
echo "ok"

# mySQL wrapps the output with a \r which is useless to us so look for the string \r and replace it with nothing
# While at that, replace all the NULLs with empty strings.
sed 's:\r::g' search_data.n.tsv | sed 's:NULL::g' > search_data.tsv
rm search_data.n.tsv

echo ""
echo "All done."
echo "The joined data has been dumped into the file called search_data.tsv."
echo "It's a tab-separated-value file that can easily be pasted into a spreadsheet to get a better look at the data."
echo "All intermediate files including the original html data has been deleted. The MySQL database tables remain."

# Clean everything up
rm kakaku.tsv
rm search.p??.html
rm newegg_results.tsv
rm newegg_search.html

exit 0
