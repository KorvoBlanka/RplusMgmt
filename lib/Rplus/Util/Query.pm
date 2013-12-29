package Rplus::Util::Query;

use Rplus::Modern;

use Rplus::DB;

use Rplus::Model::QueryCache;
use Rplus::Model::QueryCache::Manager;

use Mojo::Util qw(trim);
use Encode qw(decode_utf8);
use JSON;

# For tests (disable caching)
our $USE_CACHE = 1;

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
    my $storable_params = decode_json(shift);
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

# Parse the user's query and return Rose::DB::Object params
sub parse {
    my ($class, $q, $c) = @_; # Class, Query string, Mojolicious::Controller (for config)

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
        my ($matched, $price1, $price2);
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
                my $price = ($2 =~ s/,/./r);
                if ($ss =~ /^${rub_re}$/) {
                    $price = int($price / 1000);
                } elsif ($ss =~ /^$mln_re\s*(?:$rub_re)?$/) {
                    $price = int($price * 1000);
                } else {
                    $price = int($price);
                }
                if ($prefix eq 'от' || $prefix eq 'с') { $price1 = $price; } else { $price2 = $price; }
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
        my ($matched, $floor1, $floor2);
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
                if ($prefix eq 'до' || $prefix eq 'по') { $floor2 = $2; } else { $floor1 = $2; }
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
        }
    }

    # Square
    {
        my ($matched, $square1, $square2);
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
                if ($prefix eq 'до' || $prefix eq 'по') { $square2 = $2; } else { $square1 = $2; };
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
        }
    }

    # "Magick" phrases
    {
        # Middle floor
        if ($q =~ s/${sta_re}средн(?:\.|\w*)\s*этаж\w*${end_re}/ /i) {
            push @params, \"t1.floor > 1 AND (t1.floors_count - t1.floor) >= 1";
        }
    }

    # Technical params (based on Full Text Search)
    if ($q) {
        my $dbh = Rplus::DB->new_or_cached->dbh;

        my $_tsv2array = sub {
            my $tsv = shift;
            return unless $tsv;
            $tsv = decode_utf8($tsv);
            my @x;
            for (split(/ /, $tsv)) {
                if (/^'(\w+)':([\d,]+)$/) {
                    my ($pos, $word) = ($2, $1);
                    $x[$_] = $word for split /,/, $pos;
                }
            }
            return (grep { $_ } @x);
        };

        if (my $tsv_raw = $dbh->selectrow_arrayref("SELECT to_tsvector('russian', '".($q =~ s/'/''/gr)."')")->[0]) {
            my @tsv = $_tsv2array->($tsv_raw);
            my $tsv = join(' ', @tsv);

            my %found = (address_object => [], landmark => []);

            # First processing - technical params
            # Try to find keywords listed in query_keywords table
            {
                my @xfound;
                my $sql = "SELECT QK.* FROM query_keywords QK WHERE QK.fts @@ '".join('|', @tsv)."'::tsquery AND ts_rank_cd('{1.0, 1.0, 1.0, 1.0}', QK.fts, '".join('|', @tsv)."'::tsquery) = length(QK.fts)";
                my $sth = $dbh->prepare($sql);
                $sth->execute;
                while (my $row = $sth->fetchrow_hashref) {
                    my @x = $_tsv2array->($row->{fts});
                    push @xfound, {ftype => $row->{ftype}, fkey => $row->{fkey}, len => scalar @x, txt => join(' ', @x)};
                }

                # Delete found keywords for future processing
                for my $x (sort { $b->{len} <=> $a->{len} } @xfound) {
                    my $t = $x->{txt};
                    next if $disabled_query_items->{$x->{ftype}};
                    if ($tsv =~ s/(?:^|\s+)\Q$t\E(?:\s+|$)/ /) {
                        $found{$x->{ftype}} = [] unless exists $found{$x->{ftype}};
                        for my $y (@xfound) {
                            if ($y->{txt} eq $t) {
                                push $found{$y->{ftype}}, $y->{fkey} unless $y->{added};
                                $y->{added} = 1;
                            }
                        }
                    }
                }

                @tsv = grep { $_ } split / /, $tsv;
                $tsv = join ' ', @tsv;
            }

            # Second processing - streets
            {
                my @xfound;
                my $sql = "
                    SELECT AO.id, AO.name, AO.full_type, AO.fts2, ts_rank(AO.fts2, '".join('|', @tsv)."'::tsquery) rank
                    FROM address_objects AO
                    WHERE AO.fts @@ '".join('|', @tsv)."'::tsquery AND AO.level = 7 AND AO.curr_status = 0".($c && $c->config->{default_city_guid} ? " AND AO.parent_guid = '".$c->config->{default_city_guid}."'" : '')."
                    ORDER BY rank DESC
                    LIMIT 30
                ";
                my $sth = $dbh->prepare($sql);
                $sth->execute;
                while (my $row = $sth->fetchrow_hashref) {
                    my @x = $_tsv2array->($row->{fts2});
                    push @xfound, {ftype => 'address_object', fkey => $row->{id}, len => scalar @x, txt_a => \@x};
                }

                # Delete found keywords for future processing
                for my $x (@xfound) {
                    for my $t (@{$x->{txt_a}}) {
                        $tsv =~ s/(?:^|\s+)\Q$t\E(?:\s+|$)/ /g;
                    }
                    $found{$x->{ftype}} = [] unless exists $found{$x->{ftype}};
                    push $found{$x->{ftype}}, $x->{fkey};
                }

                @tsv = grep { $_ } split / /, $tsv;
                $tsv = join ' ', @tsv;
            }

            for my $x (keys %found) {
                next if $disabled_query_items->{$x};
                if ($x eq 'ap_scheme' || $x eq 'balcony' || $x eq 'bathroom' || $x eq 'condition' || $x eq 'house_type' || $x eq 'room_scheme') {
                    push @params, $x.'_id' => (@{$found{$x}} == 1 ? $found{$x}->[0] : $found{$x});
                } elsif ($x eq 'realty_type') {
                    # TODO: Fixme
                    push @params, \("t1.type_code IN (SELECT RT.code FROM realty_types RT WHERE RT.id IN (".join(',', @{$found{$x}})."))");
                } elsif ($x eq 'tag') {
                    push @params, tags => {ltree_ancestor => $found{$x}}; # @>
                } elsif ($x eq 'media_import') {
                    push @params, source_media_id => (@{$found{$x}} == 1 ? $found{$x}->[0] : $found{$x});
                } elsif ($x eq 'media_export') {
                    push @params, export_media => {'&&' => $found{$x}};
                }
            }

            if (@{$found{address_object}} && @{$found{landmark}}) {
                push @params, OR => [
                    address_object_id => $found{address_object},
                    landmarks => {'&&' => $found{landmark}},
                ];
            } elsif (@{$found{address_object}}) {
                push @params, address_object_id => $found{address_object};
            } elsif (@{$found{landmark}}) {
                push @params, landmarks => {'&&' => $found{landmark}};
            }

            # Other words => Full Text Search in realty
            push @params, \("t1.fts @@ '".join('|', @tsv)."'::tsquery") if @tsv;
        }
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
  use Data::Dumper;

  my $q = 'двухкомнатная квартира до 5 млн в центре';
  my @params = Rplus::Util::Query->parse($q);

  say Dumper(\@params);
  my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(query => \@params);
  ...

=head1 DESCRIPTION

L<Rplus::Util::Query> provides OO style function(s) to parse user's queries.

=head1 METHODS

L<Rplus::Util::Query> implements the following methods.

=head2 Rplus::Util::Query->parse($q, $c);

=cut
