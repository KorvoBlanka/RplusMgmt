use lib "../lib";

use Rplus::Modern;

use Test::More;

BEGIN { use_ok('Rplus::Util::Query'); }

$Rplus::Util::Query::USE_CACHE = 0;

subtest 'Price' => sub {
    for (
        ['5 тыс руб' => [price => {le => 5}]],
        ['до 10тр' => [price => {le => 10}]],
        ['от 2 млн руб' => [price => {ge => 2000}]],
        ['от 1 млн до 5 млн' => [price => {ge_le => [1000, 5000]}]],
        ['10-15тр' => [price => {ge_le => [10, 15]}]],
    ) {
        is_deeply([Rplus::Util::Query->parse($_->[0])], $_->[1], $_->[0]);
    }
};

subtest 'Rooms count' => sub {
    for (
        ['двухкомнатная' => [rooms_count => 2]],
        ['3-х комн' => [rooms_count => 3]],
        ['1-2к' => [rooms_count => {ge_le => [1, 2]}]],
    ) {
        is_deeply([Rplus::Util::Query->parse($_->[0])], $_->[1], $_->[0]);
    }
};

subtest 'Floor' => sub {
    for (
        ['1э' => [floor => {ge => 1}]],
        ['с 3 этажа по 5этаж' => [floor => {ge_le => [3, 5]}]],
        ['7-8 эт' => [floor => {ge_le => [7, 8]}]],
    ) {
        is_deeply([Rplus::Util::Query->parse($_->[0])], $_->[1], $_->[0]);
    }
};

subtest 'Square' => sub {
    for (
        ['50м' => [square_total => {ge => 50}]],
        ['от 10 до 35 кв м' => [square_total => {ge_le => [10, 35]}]],
        ['100-150 квадратных метров' => [square_total => {ge_le => [100, 150]}]],
    ) {
        is_deeply([Rplus::Util::Query->parse($_->[0])], $_->[1], $_->[0]);
    }
};

is_deeply([Rplus::Util::Query->parse('средний этаж')], [\"t1.floor > 1 AND (t1.floors_count - t1.floor) >= 1"], 'средний этаж');

done_testing();
