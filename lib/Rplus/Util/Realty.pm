package Rplus::Util::Realty;

use Rplus::Modern;

use Rplus::Model::Realty::Manager;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::RealtyType::Manager;
use Rplus::Model::MediaImportHistory;
use Rplus::Model::MediaImportHistory::Manager;

use Rplus::Util::Geo;
use Rplus::Util::Image;

use Data::Dumper;

use Exporter qw(import);

our @EXPORT_OK = qw(put_object);

my $parser = DateTime::Format::Strptime->new( pattern => '%FT%T' );
my $parser_tz = DateTime::Format::Strptime->new( pattern => '%FT%T%z' );

sub put_object {
    my ($data, $config) = @_;
    my $id;
    eval {

        if (0 && $data->{'owner_phones'} && scalar @{$data->{'owner_phones'}} > 0) {
            my $mediator = Rplus::Model::Mediator::Manager->get_objects(
              query => [
                  phone_num => [@{$data->{'owner_phones'}}],
                  delete_date => undef,
              ],
              limit => 1,
            )->[0];

            return undef if ($mediator && $data->{offer_type_code} eq 'rent');
        }

        # check add_date
        if ($data->{add_date}) {
            my $now_dt = DateTime->now(time_zone => 'local');
            say $data->{add_date};
            my $d_dt = $parser_tz->parse_datetime($data->{add_date});
            say $d_dt;
            if ($d_dt > $now_dt) {
                say "wtf? obj from future";
                $data->{add_date} = undef;
            }
        }

        my @realtys = @{_find_similar(%$data, state_code => ['raw', 'work', 'suspended', 'deleted'])};
        if (scalar @realtys > 0) {
            foreach (@realtys) {
                $id = $_->id;   # что если похожий объект не один? какой id возвращать?
                my $o_realty = $_;
                say "Found similar realty: $id";

                if ($data->{add_date} && $o_realty->last_seen_date) {
                    # пропустим если объект в базе "новее"

                    say $data->{add_date};
                    say $o_realty->last_seen_date;

                    my $o_dt = $parser->parse_datetime($o_realty->last_seen_date);
                    my $n_dt = $parser_tz->parse_datetime($data->{add_date});

                    if ($o_dt && $n_dt && ($o_dt >= $n_dt)) {
                        say 'newer!';
                        next;
                    }
                }

                my @phones = ();
                foreach (@{$o_realty->owner_phones}) {
                    push @phones, $_;
                }

                $o_realty->owner_phones(Mojo::Collection->new(@phones)->compact->uniq);
                if ($data->{add_date}) {
                    $o_realty->last_seen_date($data->{add_date});
                } else {
                    $o_realty->last_seen_date('now()');
                }
                $o_realty->change_date('now()');

                if ($o_realty->state_code ne 'work') {
                    my @fields = qw(type_code source_media_id source_url source_media_text locality address house_num owner_price ap_scheme_id rooms_offer_count rooms_count condition_id room_scheme_id house_type_id floors_count floor square_total square_living square_kitchen square_land square_land_type);
                    foreach (@fields) {
                        $o_realty->$_($data->{$_}) if $data->{$_};
                    }
                }

                _update_location($o_realty);

                $o_realty->save(changes_only => 1);
                say "updated realty: $id";

                _update_photos($id, $config->{storage}->{path}, $data->{photo_url});
            }
        } else {
            my $realty = Rplus::Model::Realty->new((map { $_ => $data->{$_} } grep { $_ ne 'photo_url' && $_ ne 'id' && $_ ne 'category_code'} keys %$data), state_code => 'raw');
            if ($data->{add_date}) {
                $realty->last_seen_date($data->{add_date});
            } else {
                $realty->last_seen_date('now()');
            }

            _update_location($realty, $config);

            $realty->save;
            my $data_id = $data->{id};
            $id = $realty->id;
            say "Saved new realty: $id";

            _update_photos($id, $config->{storage}->{path}, $data->{photo_url});
        }
    } or do {
        say $@;
    };

    return $id;
}

sub _find_similar {
    my %data = @_;

    return unless %data;
    return unless $data{'type_code'};
    return unless $data{'offer_type_code'};
    return unless $data{'state_code'};

    # Определим категорию недвижимости
    my $realty_type = Rplus::Model::RealtyType::Manager->get_objects(query => [code => $data{'type_code'}])->[0];
    return unless $realty_type;
    my $category_code = $realty_type->category_code;

    #
    # Поиск по тексту объявления
    #
    if (1 == 2 && $data{'source_media_text'}) {     # выключим проверку на тексту объявления, посмотрим что получится
        # Поиск в таблице недвижимости по тексту объявления
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            #select => 'id',
            query => [
                source_media_text => $data{'source_media_text'},

                type_code => $data{'type_code'},
                offer_type_code => $data{'offer_type_code'},
                #state_code => $data{'state_code'},
                ($data{'id'} ? ('!id' => $data{'id'}) : ()),
            ],
            limit => 10,
        );
        return $realty if scalar @{$realty} > 0;

        # Поиск в таблице истории импорта по тексту объявления
        my $mih = Rplus::Model::MediaImportHistory::Manager->get_objects(
            select => 'id, realty_id',
            query => [
                media_text => $data{'source_media_text'},
                'realty.type_code' => $data{'type_code'},
                'realty.offer_type_code' => $data{'offer_type_code'},
                'realty.state_code' => $data{'state_code'},
                ($data{'id'} ? ('!realty_id' => $data{'id'}) : ()),
            ],
            require_objects => ['realty'],
            limit => 1
        )->[0];
        return $mih->realty_id if $mih;
    }

    #
    # Универсальное правило
    # Совпадение: один из номеров телефонов + проверка по остальным параметрам
    #
    if (ref($data{'owner_phones'}) eq 'ARRAY' && @{$data{'owner_phones'}}) {
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            #select => 'id',
            query => [
                \("owner_phones && '{".join(',', map { '"'.$_.'"' } @{$data{'owner_phones'}})."}'"),

                type_code => $data{'type_code'},
                offer_type_code => $data{'offer_type_code'},
                locality => $data{'locality'}, address => $data{'address'}, house_num => $data{'house_num'},
                #state_code => $data{'state_code'},

                ($data{'id'} ? ('!id' => $data{'id'}) : ()),

                ($data{'ap_num'} ? (OR => [ap_num => $data{'ap_num'}, ap_num => undef]) : ()),
                ($data{'rooms_count'} ? (OR => [rooms_count => $data{'rooms_count'}, rooms_count => undef]) : ()),
                ($data{'rooms_offer_count'} ? (OR => [rooms_offer_count => $data{'rooms_offer_count'}, rooms_offer_count => undef]) : ()),
                ($data{'floor'} ? (OR => [floor => $data{'floor'}, floor => undef]) : ()),
                ($data{'floors_count'} ? (OR => [floors_count => $data{'floors_count'}, floors_count => undef]) : ()),
                ($data{'square_total'} ? (OR => [square_total => $data{'square_total'}, square_total => undef]) : ()),
                ($data{'square_living'} ? (OR => [square_living => $data{'square_living'}, square_living => undef]) : ()),
                ($data{'square_land'} ? (OR => [square_land => $data{'square_land'}, square_land => undef]) : ()),
            ],
            limit => 10,
        );
        return $realty if scalar @{$realty} > 0;
    }

    # Недвижимость чистая
    return [];
}

sub _update_location {
    my $realty = shift;
    my $config = shift;
    if ($realty->address) {
        my %coords = Rplus::Util::Geo::get_coords_by_addr($realty->locality, $realty->address, $realty->house_num);

        if (%coords) {

            say 'yay, coords!';

            $realty->latitude($coords{latitude});
            $realty->longitude($coords{longitude});
        }
    }

    if ($realty->latitude) {
        my $res = Rplus::Util::Geo::get_location_metadata($realty->latitude, $realty->longitude, $config);

        $realty->district(join ', ', @{$res->{district}});
        $realty->pois($res->{pois});
    }
}

sub _update_photos {
    my ($realty_id, $storage_path, $photos) = @_;

    Rplus::Util::Image::remove_images($realty_id);

    for my $photo_url (@{$photos}) {
        say 'loading ' . $photo_url;
        #Rplus::Util::Image::load_image_from_url($realty_id, $photo_url, $storage_path, 0);
        Rplus::Util::Image::put_external_image($realty_id, $photo_url, $photo_url)
    }
}

1;
