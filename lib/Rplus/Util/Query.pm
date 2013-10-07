package Rplus::Util::Query;

use Rplus::Modern;

use Mojo::Util qw(trim);

sub parse {
    my $class = shift;
    my $text = shift;
    my $ts_query_text_ref = shift;
    #my %options = @_;

    return unless $text;

    # Rose::DB::Object query format
    my @params;

    my $sta_re = qr/(?:^|\s+|,\s*)/;
    my $end_re = qr/(?:\s+|,|$)/;
    my $tofrom_re = qr/(?:от|до|с|по)/;

    # Цена
    {
        my ($matched, $price1, $price2);
        do {
            $matched = 0;

            my $float_re = qr/\d+(?:[,.]\d+)?/;
            my $rub_re = qr/р(?:\.|(?:уб(?:\.|лей)?)?)?/;
            my $ths_re = qr/т(?:\.|(ыс(?:\.|яч)?)?)?/;
            my $mln_re = qr/(?:(?:млн\.?)|(?:миллион\w*))/;

            # Диапазон
            if ($text =~ s/${sta_re}(?:(?:от|с)\s+)?(${float_re})\s*(?:до|по|-)\s*(${float_re})\s*((?:${rub_re})|(?:${ths_re}\s*${rub_re})|(?:$mln_re\s*(?:$rub_re)?))${end_re}/ /i) {
                my $ss = $3;
                ($price1, $price2) = map { s/,/./r } ($1, $2);
                if ($ss =~ /^${rub_re}$/) {
                    ($price1, $price2) = (map { int($_ / 1000) } ($price1, $price2));
                } elsif ($ss =~ /^$mln_re\s*(?:$rub_re)?$/) {
                    ($price1, $price2) = (map { int($_ * 1000) } ($price1, $price2));
                } else {
                    ($price1, $price2) = (map { int($_) } ($price1, $price2));
                };
            }
            # Одиночное значение
            elsif ($text =~ s/${sta_re}(?:(${tofrom_re})\s+)?(${float_re})\s*((?:${rub_re})|(?:${ths_re}\s*${rub_re})|(?:$mln_re\s*(?:$rub_re)?))${end_re}/ /i) {
                my $prefix = $1 || '';
                my $ss = $3;
                my $price = ($2 =~ s/,/./r);
                if ($ss =~ /^${rub_re}$/) {
                    $price = int($price / 1000);
                } elsif ($ss =~ /^$mln_re\s*(?:$rub_re)?$/) {
                    $price = int($price * 1000);
                } else {
                    $price = int($price);
                };
                if ($prefix eq 'от' || $prefix eq 'с') { $price1 = $price; } else { $price2 = $price };
                $matched = 1;
            }
        } while ($matched);

        $text = trim($text) if $matched;

        if ($price1 && $price2) {
            push @params, price => {ge_le => [$price1, $price2]};
        } elsif ($price1) {
            push @params, price => {ge => $price1};
        } elsif ($price2) {
            push @params, price => {le => $price2};
        }
    }

    # Количество комнат
    {
        my ($matched, $rooms_count);
        do {
            $matched = 0;

            # N комн.
            if ($text =~ s/${sta_re}(\d)(?:-?х\s)?\s*к(?:\.|(?:омн(?:\.|ат\w*)?)?)?${end_re}/ /i) {
                $rooms_count = $1;
                $matched = 1;
            }
            # [одно|двух|...]комнатная
            elsif ($text =~ s/${sta_re}(одно|одна|двух|трех|четырех|пяти|шести|семи|восьми|девяти)\s*комн(?:\.|(?:ат\w*)?)?${end_re}/ /i) {
                $rooms_count = 1 if $1 eq 'одно' || $1 eq 'одна';
                $rooms_count = 2 if $1 eq 'двух';
                $rooms_count = 3 if $1 eq 'трех';
                $rooms_count = 4 if $1 eq 'четырех';
                $rooms_count = 5 if $1 eq 'пяти';
                $rooms_count = 6 if $1 eq 'шести';
                $rooms_count = 7 if $1 eq 'семи';
                $rooms_count = 8 if $1 eq 'восьми';
                $rooms_count = 9 if $1 eq 'девяти';
                $matched = 1;
            }
        } while ($matched);

        $text = trim($text) if $matched;

        if ($rooms_count) {
            push @params, rooms_count => $rooms_count;
        }
    }

    # Этаж
    {
        my ($matched, $floor1, $floor2);
        do {
            $matched = 0;

            my $flr_re = qr/э(?:\.|(?:т(?:\.|аж\w*)?)?)?/;

            # Диапазон
            if ($text =~ s/${sta_re}(?:(?:от|с)\s+)?(\d{1,2})\s*(?:до|по|-)\s*(\d{1,2})\s*${flr_re}${end_re}/ /i) {
                ($floor1, $floor2) = ($1, $2);
            }
            # Одиночное значение
            elsif ($text =~ s/${sta_re}(?:(${tofrom_re})\s+)?(\d{1,2})\s*${flr_re}${end_re}/ /i) {
                my $prefix = $1 || '';
                if ($prefix eq 'до' || $prefix eq 'по') { $floor2 = $2; } else { $floor1 = $2; };
                $matched = 1;
            }
        } while ($matched);

        $text = trim($text) if $matched;

        if ($floor1 && $floor2) {
            push @params, floor => {ge_le => [$floor1, $floor2]};
        } elsif ($floor1) {
            push @params, floor => {ge => $floor1};
        } elsif ($floor2) {
            push @params, floor => {le => $floor2};
        }
    }

    # Площадь
    {
        my ($matched, $square1, $square2);
        do {
            $matched = 0;

            my $sqr_re = qr/(?:кв(?:\.|адратн\w*)?)?\s*м(?:\.|2|етр\w*)?/;

            # Диапазон
            if ($text =~ s/${sta_re}(?:(?:от|с)\s+)?(\d+)\s*(?:до|по|-)\s*(\d+)\s*${sqr_re}${end_re}/ /i) {
                ($square1, $square2) = ($1, $2);
            }
            # Одиночное значение
            elsif ($text =~ s/${sta_re}(?:(${tofrom_re})\s+)?(\d+)\s*${sqr_re}${end_re}/ /i) {
                my $prefix = $1 || '';
                if ($prefix eq 'до' || $prefix eq 'по') { $square2 = $2; } else { $square1 = $2; };
                $matched = 1;
            }
        } while ($matched);

        $text = trim($text) if $matched;

        if ($square1 && $square2) {
            push @params, or => [
                square_total => {ge_le => [$square1, $square2]},
                square_living => {ge_le => [$square1, $square2]},
            ];
        } elsif ($square1) {
            push @params, or => [
                square_total => {ge => $square1},
                square_living => {ge => $square1},
            ];
        } elsif ($square2) {
            push @params, or => [
                square_total => {le => $square2},
                square_living => {le => $square2},
            ];
        }
    }

    # Некоторые особые фразы
    {
        if ($text =~ s/${sta_re}средн(?:\.|\w*)\s*этаж\w*${end_re}/ /i) {
            push @params, \"floor > 1 AND (floors_count - floor) >= 1";
        }
    }

    # Text for future processing
    $$ts_query_text_ref = $text if $text;

    return wantarray ? @params : \@params;
}

1;
