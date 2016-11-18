#!/bin/bash
# ffbx-livemarks.sh - Firefox livemarks extractor - extract livemarks from user profiles.
# Copyright (C) 2014-2015 Thomas Szteliga <ts@websafe.pl>, <https://websafe.pl/>
# Copyright (C) 2016 Chris Barts <chbarts@gmail.com>
#
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
#
# ------------------------------------------------------------------------------

IFS="
"

#
CMD_CUT=${CMD_CUT:-$(which cut)}
CMD_FIND=${CMD_FIND:-$(which find)}
CMD_SQLITE3=${CMD_SQLITE3:-$(which sqlite3)}
CMD_TR=${CMD_TR:-$(which tr)}
CMD_UNIQ=${CMD_UNIQ:-$(which uniq)}

if [ ! -f "${CMD_CUT}" ]; then
    echo "cut not found" >/dev/stderr
    exit 1
fi

if [ ! -f "${CMD_FIND}" ]; then
    echo "find not found" >/dev/stderr
    exit 1
fi

if [ ! -f "${CMD_SQLITE3}" ]; then
    echo "sqlite3 not found" >/dev/stderr
    exit 1
fi

if [ ! -f "${CMD_TR}" ]; then
    echo "tr not found" >/dev/stderr
    exit 1
fi

if [ ! -f "${CMD_UNIQ}" ]; then
    echo "uniq not found" >/dev/stderr
    exit 1
fi

# 
FFBX_FIELD_SEPARATOR=${FFBX_FIELD_SEPARATOR:-"\t"}
FFBX_ROW_SEPARATOR=${FFBX_ROW_SEPARATOR:-"\n"}
FFBX_ITEM_SEPARATOR=${FFBX_ITEM_SEPARATOR:-","}

# ------------------------------------------------------------------------------

#
#
#
function debug() {
    if [ "${DEBUG}" = "1" ];
    then
        local msg="${*}"
        echo "DEBUG: $msg"
    fi
}

# ------------------------------------------------------------------------------

#
if [ -z "${1}" ];
then
    #
    found_db_places_paths=$(
        #
        ${CMD_FIND} ~/.mozilla/firefox/ \
            -type f \
            -name "places.sqlite" \
            -mindepth 2 \
            -maxdepth 2 \
            2>/dev/null
    )
    #
    if [ -z "${found_db_places_paths}" ];
    then
        echo "No places.sqlite path given and none could be found."
        exit 1
    else
        db_places_paths_were_autodiscovered="yes"
    fi
else
    #
    if [ ! -r "${1}" ];
    then
        echo "Profile path is not readable."
        exit 2
    else
        found_db_places_paths="${1}"
        db_places_paths_were_autodiscovered="no"
    fi
fi

debug "found_db_places_paths ${found_db_places_paths}"
debug "db_places_paths_were_autodiscovered" \
        "${db_places_paths_were_autodiscovered}"

# ------------------------------------------------------------------------------

#
for db_places_path in ${found_db_places_paths};
do

    profile_path=$(dirname "${db_places_path}")
    profile_name=$(basename "${profile_path}")

    # Retrieve list of livemarks data with lastModified timestamp
    livemarks_data=$(
        ${CMD_SQLITE3} "${db_places_path}" \
        "SELECT lastModified,id FROM moz_bookmarks
            WHERE type=2 ORDER BY lastModified"
    )

    # Filter the obtained list for distinct places ids ordered
    # by lastModified timestamp:
    livemarks_places_ids=$(
        echo "${livemarks_data}" \
            | ${CMD_CUT} -d'|' -f2 \
            | ${CMD_UNIQ}
    )

    debug "livemarks_places_ids ${livemarks_places_ids}"

    #
    for livemark_places_id in ${livemarks_places_ids};
    do

        debug "livemark_places_id ${livemark_places_id}"

        # Retrieve the livemark URL:
        livemark_url=$(
            ${CMD_SQLITE3} "${db_places_path}" \
                "SELECT content FROM moz_items_annos
                    WHERE id=${livemark_places_id} AND anno_attribute_id=10" \
                | ${CMD_TR} -d "\n" \
                | ${CMD_TR} -d "\r"
        )

        # If there is no URL, this is just a folder, and move on
        if [ -z "${livemark_url}" ]; then
            continue
        fi
        
        debug "livemark_url ${livemark_url}"

        # Retrieve the livemark's site URL:
        livemark_site_url=$(
            ${CMD_SQLITE3} "${db_places_path}" \
                "SELECT content FROM moz_items_annos
                    WHERE id=${livemark_places_id} AND anno_attribute_id=11" \
                | ${CMD_TR} -d "\n" \
                | ${CMD_TR} -d "\r"
        )

        debug "livemark_site_url ${livemark_site_url}"

        # Retrieve the title:
        livemark_title=$(
            ${CMD_SQLITE3} "${db_places_path}" \
                "SELECT title FROM moz_bookmarks
                    WHERE id=${livemark_places_id} AND title!='' LIMIT 1"
        )

        debug "livemark_title ${livemark_title}"

        # Retrieve last modification timestamp for the current livemark:
        livemark_last_modification=$(
            ${CMD_SQLITE3} "${db_places_path}" \
                "SELECT lastModified FROM moz_bookmarks
                    WHERE id=${livemark_places_id} 
                    ORDER BY lastModified DESC LIMIT 1"
        )

        debug "livemark_last_modification ${livemark_last_modification}"

        # Retrieve added timestamp for the current livemark:
        livemark_date_added=$(
            ${CMD_SQLITE3} "${db_places_path}" \
                "SELECT dateAdded FROM moz_bookmarks
                    WHERE id=${livemark_places_id} 
                    ORDER BY dateAdded DESC LIMIT 1"
        )

        debug "livemark_date_added ${livemark_date_added}"

        # Retrieve id of current livemarks parent folder:
        livemark_folder_id=$(
            ${CMD_SQLITE3} "${db_places_path}" \
                "SELECT parent FROM moz_bookmarks
                    WHERE type=2 AND id=${livemark_places_id}
                    ORDER BY id ASC LIMIT 1"
        )

        debug "livemark_folder_id ${livemark_folder_id}"

        # Retrieve the name of current livemarks parent folder:
        livemark_folder_name=$(
            ${CMD_SQLITE3} "${db_places_path}" \
                "SELECT title FROM moz_bookmarks
                    WHERE id=${livemark_folder_id}"
        )

        debug "livemark_folder_name ${livemark_folder_name}"

        # Output CSV data:
        echo -ne "${livemark_last_modification}"
        echo -ne "${FFBX_FIELD_SEPARATOR}"
        echo -ne "${livemark_date_added}"
        if [ "${db_places_paths_were_autodiscovered}" = "yes" ];
        then
            echo -ne "${FFBX_FIELD_SEPARATOR}"
            echo -n "${profile_name}" | ${CMD_TR} "\t" " "
        fi
        #echo -ne "${FFBX_FIELD_SEPARATOR}"
        #echo -n "${profile_path}"
        #echo -ne "${FFBX_FIELD_SEPARATOR}"
        #echo -n "${bookmark_places_id}"
        echo -ne "${FFBX_FIELD_SEPARATOR}"
        echo -n "${livemark_folder_name}" | ${CMD_TR} "\t" " "
        echo -ne "${FFBX_FIELD_SEPARATOR}"
        echo -n "${livemark_url}" | ${CMD_TR} "\t" " "
        echo -ne "${FFBX_FIELD_SEPARATOR}"
        echo -n "${livemark_site_url}" | ${CMD_TR} "\t" " "
        echo -ne "${FFBX_FIELD_SEPARATOR}"
        echo -n "${livemark_title}" | ${CMD_TR} "\t" " "
        echo -ne "${FFBX_ROW_SEPARATOR}"
    done
done
