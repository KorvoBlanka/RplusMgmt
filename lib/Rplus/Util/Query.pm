package Rplus::Util::Query;

use Rplus::Modern;

use Rplus::DB;

use Rplus::Model::QueryCache;
use Rplus::Model::QueryCache::Manager;

use Mojo::Util qw(trim);
use Encode qw(decode_utf8);
use JSON;

no warnings 'experimental::smartmatch';

my $ua = Mojo::UserAgent->new;

# For tests (disable caching)
our $USE_CACHE = 0;

# Rose::DB::Object params to JSON
sub _params2json {
    my $storable_params = [];
    for (@_) {
        if (ref($_) eq 'SCALAR') {
            push @$storable_params, {ref => $$_};
        } else {
            push @$storable_params, $_;
        }
    }
    return encode_json($storable_params);
}

# JSON to Rose::DB::Object params
sub _json2params {
    my $storable_params = from_json(shift);
    my @params;
    for (@$storable_params) {
        if (ref($_) eq 'HASH' && $_->{ref}) {
            push @params, \($_->{ref});
        } else {
            push @params, $_;
        }
    }
    return @params;
}


sub get_near_filter {
    my ($near_q, $self) = @_;
    my @points;

    my $data = $ua->get(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
        form => {
          #language => 'ru',
          location => $self->config->{location}->{lat} . ',' . $self->config->{location}->{lng},
          radius => $self->config->{search}->{places_radius},
          query => $near_q,
          key => $self->config->{api_keys}->{google},
        }
    )->res->json;

    foreach (@{$data->{results}}) {

        push @points, {
            lat => $_->{geometry}->{location}->{lat},
            lon => $_->{geometry}->{location}->{lng}
        };
    }

    my $max_points = 100;

    my @near_query = ();
    foreach (@points) {
        if ((scalar @near_query) == $max_points) {last};
        push @near_query,
        \("postgis.st_distance(t1.geocoords, postgis.ST_GeographyFromText('SRID=4326;POINT(" . $_->{lon} . " " . $_->{lat} . ")'), true) < " . $self->config->{search}->{radius});
    }

    return or => \@near_query;

}

# Parse the user's query and return Rose::DB::Object params
sub parse {
    my ($q, $c) = @_; # Class, Query string, Mojolicious::Controller (for config)

    return unless $q;
    my $q_orig = $q = trim($q);

    # Disabled params
    my $disabled_query_items = {map { $_ => 1 } @{($c && $c->config->{disabled_query_items}) || []}};

    # Rose::DB::Object query format
    my @params;

    # Check for cached query existence
    if ($USE_CACHE) {
        my $query_cache_lifetime = ($c && $c->config->{query_cache_lifetime}) || '1 day';
        if (my $qc = Rplus::Model::QueryCache::Manager->get_objects(query => [query => $q, \"add_date >= now() - interval '$query_cache_lifetime'"])->[0]) {
            return _json2params($qc->params);
        }
    }

    # Some commonly used regexes
    my $sta_re = qr/(?:^|\s+|,\s*)/;
    my $end_re = qr/(?:\s+|,|$)/;
    my $tofrom_re = qr/(?:от|до|с|по)/;

    #
    # Recognition blocks
    #


    # Price
    {
        my ($matched, $price1, $price2, $price);
        do {
            $matched = 0;

            my $float_re = qr/\d+(?:[,.]\d+)?/;
            my $rub_re = qr/р(?:\.|(?:уб(?:\.|лей)?)?)?/;
            my $ths_re = qr/т(?:\.|(ыс(?:\.|яч)?)?)?/;
            my $mln_re = qr/(?:(?:млн\.?)|(?:миллион\w*))/;

            # Range
            if ($q =~ s/${sta_re}(?:(?:от|с)\s+)?(${float_re})\s*(?:до|по|\-)\s*(${float_re})\s*((?:${rub_re})|(?:${ths_re}\s*${rub_re})|(?:$mln_re\s*(?:$rub_re)?))${end_re}/ /i) {
                my $ss = $3;
                ($price1, $price2) = map { s/,/./r } ($1, $2);
                if ($ss =~ /^${rub_re}$/) {
                    ($price1, $price2) = (map { int($_ / 1000) } ($price1, $price2));
                } elsif ($ss =~ /^$mln_re\s*(?:$rub_re)?$/) {
                    ($price1, $price2) = (map { int($_ * 1000) } ($price1, $price2));
                } else {
                    ($price1, $price2) = (map { int($_) } ($price1, $price2));
                }
            }
            # Single value
            elsif ($q =~ s/${sta_re}(?:(${tofrom_re})\s+)?(${float_re})\s*((?:${rub_re})|(?:${ths_re}\s*${rub_re})|(?:$mln_re\s*(?:$rub_re)?))${end_re}/ /i) {
                my $prefix = $1 || '';
                my $ss = $3;
                $price = ($2 =~ s/,/./r);
                if ($ss =~ /^${rub_re}$/) {
                    $price = int($price / 1000);
                } elsif ($ss =~ /^$mln_re\s*(?:$rub_re)?$/) {
                    $price = int($price * 1000);
                } else {
                    $price = int($price);
                }
                if ($prefix eq 'от' || $prefix eq 'с') { $price1 = $price; };
                if ($prefix eq 'до' || $prefix eq 'по') { $price2 = $price; };

                $matched = 1;
            }
        } while ($matched);

        $q = trim($q) if $matched;

        if ($price1 && $price2) {
            push @params, price => {ge_le => [$price1, $price2]};
        } elsif ($price1) {
            push @params, price => {ge => $price1};
        } elsif ($price2) {
            push @params, price => {le => $price2};
        } elsif ($price) {
            push @params, price => $price;
        }
    }

    # Rooms count
    {
        my ($matched, $rooms_count, $rooms_count1, $rooms_count2);
        do {
            $matched = 0;

            # Range
            if ($q =~ s/${sta_re}(\d)\s*\-\s*(\d)\s*к(?:\.|(?:омн(?:\.|ат\w*)?)?)?${end_re}/ /i) {
                ($rooms_count1, $rooms_count2) = ($1, $2);
            }
            # Single value: N комн.
            elsif ($q =~ s/${sta_re}(\d)(?:\-?х\s)?\s*к(?:\.|(?:омн(?:\.|ат\w*)?)?)?${end_re}/ /i) {
                $rooms_count = $1;
                $matched = 1;
            }
            # Single value: [одно|двух|...]комнатная
            elsif ($q =~ s/${sta_re}(одн[оа]|двух|трех|четырех|пяти|шести|семи|восьми|девяти)\s*комн(?:\.|(?:ат\w*)?)?${end_re}/ /i) {
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

        $q = trim($q) if $matched;

        if ($rooms_count1 && $rooms_count2) {
            push @params, rooms_count => {ge_le => [$rooms_count1, $rooms_count2]};
        } elsif ($rooms_count) {
            push @params, rooms_count => $rooms_count;
        }
    }

    # Floor
    {
        my ($matched, $floor1, $floor2, $floor);
        do {
            $matched = 0;

            my $flr_re = qr/э(?:\.|(?:т(?:\.|аж\w*)?)?)?/;

            # Range
            if ($q =~ s/${sta_re}(?:(?:от|с)\s+)?(\d{1,2})\s*(?:до|по|\-)\s*(\d{1,2})\s*${flr_re}${end_re}/ /i) {
                ($floor1, $floor2) = ($1, $2);
            }
            # Single value
            elsif ($q =~ s/${sta_re}(?:(${tofrom_re})\s+)?(\d{1,2})\s*${flr_re}${end_re}/ /i) {
                my $prefix = $1 || '';
                $floor = $2;
                if ($prefix eq 'от' || $prefix eq 'с') { $floor1 = $floor; };
                if ($prefix eq 'до' || $prefix eq 'по') { $floor2 = $floor; };
                $matched = 1;
            }
        } while ($matched);

        $q = trim($q) if $matched;

        if ($floor1 && $floor2) {
            push @params, floor => {ge_le => [$floor1, $floor2]};
        } elsif ($floor1) {
            push @params, floor => {ge => $floor1};
        } elsif ($floor2) {
            push @params, floor => {le => $floor2};
        } elsif ($floor) {
            push @params, floor => $floor;
        }
    }

    # Square
    {
        my ($matched, $square1, $square2, $square);
        do {
            $matched = 0;

            my $sqr_re = qr/(?:кв(?:\.|адратн\w*)?)?\s*м(?:\.|2|етр\w*)?/;

            # Range
            if ($q =~ s/${sta_re}(?:(?:от|с)\s+)?(\d+)\s*(?:до|по|\-)\s*(\d+)\s*${sqr_re}${end_re}/ /i) {
                ($square1, $square2) = ($1, $2);
            }
            # Single value
            elsif ($q =~ s/${sta_re}(?:(${tofrom_re})\s+)?(\d+)\s*${sqr_re}${end_re}/ /i) {
                my $prefix = $1 || '';
                $square = $2;
                if ($prefix eq 'от' || $prefix eq 'с') { $square1 = $square; };
                if ($prefix eq 'до' || $prefix eq 'по') { $square2 = $square; };
                $matched = 1;
            }
        } while ($matched);

        $q = trim($q) if $matched;

        if ($square1 && $square2) {
            push @params, square_total => {ge_le => [$square1, $square2]};
        } elsif ($square1) {
            push @params, square_total => {ge => $square1};
        } elsif ($square2) {
            push @params, square_total => {le => $square2};
        } elsif ($square) {
            push @params, square_total => $square;
        }
    }

    # "Magick" phrases
    {
        # Middle floor
        if ($q =~ s/${sta_re}средн(?:\.|\w*)\s*этаж\w*${end_re}/ /i) {
            push @params, \"t1.floor > 1 AND (t1.floors_count - t1.floor) >= 1";
        }
    }

    given ($q) {
        when (/(^|\s+)дача($|\s+)/i) {
          push @params, type_code => 'dacha';
          $q =~ s/дача//i;
        }

        when (/(^|\s+)дом($|\s+)/i) {
            push @params, type_code => 'house';
            $q =~ s/дом//i;
        }

        when (/(^|\s+)квартира($|\s+)/i) {
            push @params, type_code => 'apartment';
            $q =~ s/квартира//i;
        }

        when (/(^|\s+)коттедж($|\s+)/i) {
            push @params, type_code => 'cottage';
            $q =~ s/коттедж//i;
        }

        when (/(^|\s+)таунхаус($|\s+)/i) {
            push @params, type_code => 'townhouse';
            $q =~ s/таунхаус//i;
        }

        when (/(^|\s+)малосемейка($|\s+)/i) {
            push @params, type_code => 'apartment_small';
            $q =~ s/малосемейка//i;
        }

        when (/(^|\s+)новостройка($|\s+)/i) {
            push @params, type_code => 'apartment_new';
            $q =~ s/новостройка//i;
        }

        when (/(^|\s+)комната($|\s+)/i) {
            push @params, type_code => 'room';
            $q =~ s/комната//i;
        }

        when (/(^|\s+)земельный участок($|\s+)/i) {
            push @params, type_code => 'land';
            $q =~ s/земельный участок//i;
        }

        when (/(^|\s+)земля($|\s+)/i) {
            push @params, type_code => 'land';
            $q =~ s/земля//i;
        }

        when (/(^|\s+)участок($|\s+)/i) {
            push @params, type_code => 'land';
            $q =~ s/участок//i;
        }

        when (/(^|\s+)офис($|\s+)/i) {
            push @params, type_code => 'office_place';
            $q =~ s/офис//i;
        }

        when (/(^|\s+)торговая площадь($|\s+)/i) {
            push @params, type_code => 'market_place';
            $q =~ s/торговая площадь//i;
        }

        when (/(^|\s+)гараж($|\s+)/i) {
            push @params, type_code => 'garage';
            $q =~ s/гараж//i;
        }

        when (/(^|\s+)здание($|\s+)/i) {
            push @params, type_code => 'building';
            $q =~ s/здание//i;
        }

        when (/(^|\s+)производственное помещение($|\s+)/i) {
            push @params, type_code => 'production_place';
            $q =~ s/производственное помещение//i;
        }

        when (/(^|\s+)помещение свободного назначения($|\s+)/i) {
            push @params, type_code => 'gpurpose_place';
            $q =~ s/помещение свободного назначения//i;
        }

        when (/(^|\s+)помещение под автобизнес($|\s+)/i) {
            push @params, type_code => 'autoservice_place';
            $q =~ s/помещение под автобизнес//i;
        }

        when (/(^|\s+)помещение под сферу услуг($|\s+)/i) {
            push @params, type_code => 'service_place';
            $q =~ s/помещение под сферу услуг//i;
        }

        when (/(^|\s+)склад($|\s+)/i) {
            push @params, type_code => 'warehouse_place';
            $q =~ s/склад//i;
        }

        when (/(^|\s+)база($|\s+)/i) {
            push @params, type_code => 'warehouse_place';
            $q =~ s/база//i;
        }
    }

    # fts address search
    if ($q) {
      if ($q =~ s/"(.*?)"// ) {
        push @params, \("t1.fts @@ plainto_tsquery('english', '" . $1 . "')");
      }
    }

    # FTS tag search
    if ($q !~ /^\s*$/) {
      push @params, \("t1.fts_vector @@ plainto_tsquery('russian', '" . $q . "')");
    }

    Rplus::Model::QueryCache->new(query => $q_orig, params => _params2json(@params))->save if $USE_CACHE && @params;

    return wantarray ? @params : \@params;
}

1;

=encoding utf8

=head1 NAME

Rplus::Util::Query - User's query parser

=head1 SYNOPSIS

  use Rplus::Model::Realty::Manager;
  use Rplus::Util::Query;

  my $q = 'двухкомнатная квартира до 5 млн в центре';
  my @params = Rplus::Util::Query->parse($q);

  my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(query => \@params);
  ...

=head1 DESCRIPTION

L<Rplus::Util::Query> provides OO style function(s) to parse user's queries.

=head1 METHODS

L<Rplus::Util::Query> implements the following methods.

=head2 Rplus::Util::Query->parse($q, $c);

=cut
