#!/bin/bash

set -o nounset
set -o errexit

function get_data {
    
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    wget http://files.grouplens.org/datasets/movielens/ml-10m.zip
    unzip ml-10m.zip
    iconv -f iso-8859-1 -t utf-8 ml-10M100K/movies.dat -o ml-10M100K/movies.dat.utf8

}

function create_csv {

    echo "create items csv"
    cat <(echo 'id,title,genre') <(cat ml-10M100K/movies.dat.utf8 | sed "s/::/\t/g" | awk -F '\t' '{printf("%d,\"%s\",\"%s\"\n",$1,$2,$3)}') > items.csv

    cd ml-10M100K/; ./split_ratings.sh; cd ..

    echo "create users csv"
    cat <(echo "id") <(cat ml-10M100K/r1.train | sed "s/::/\|/g" | cut -d'|' -f1 | sort -n | uniq) > users.csv

    echo "create actions csv"
    cat <(echo "user_id,item_id,value,time") <(cat ml-10M100K/r1.train | sed "s/::/\|/g" | cut -d'|' -f1,2,3,4 --output-delimiter=,) > actions.csv

}

function setup_client {

    seldon-cli client --action setup --client-name ml10m100k --db-name ClientDB10m
    seldon-cli attr --action apply --client-name ml10m100k --json attr.json
    seldon-cli import --action items --client-name ml10m100k --file-path items.csv
    seldon-cli import --action users --client-name ml10m100k --file-path users.csv
    seldon-cli import --action actions --client-name ml10m100k --file-path actions.csv
}

function build_model {

    luigi --module seldon.luigi.spark SeldonMatrixFactorization --local-schedule --client ml10m100k --startDay 1

}

function configure_runtime_scorer {

    cat <<EOF | seldon-cli rec_alg --action create --client-name ml10m100k -f -
{
    "defaultStrategy": {
        "algorithms": [
            {
                "config": [
                    {
                        "name": "io.seldon.algorithm.general.numrecentactionstouse",
                        "value": "1"
                    }
                ],
                "filters": [],
                "includers": [],
                "name": "recentMfRecommender"
            }
        ],
        "combiner": "firstSuccessfulCombiner",
        "diversityLevel": 3
    },
    "recTagToStrategy": {}
}
EOF
    seldon-cli rec_alg --action commit --client-name ml10m100k
}

function create_recommender {

    STARTUP_DIR="$( cd "$( dirname "$0" )" && pwd )"
    cd ${STARTUP_DIR}
    
    get_data

    create_csv

    setup_client

    build_model

    configure_runtime_scorer
}


create_recommender

