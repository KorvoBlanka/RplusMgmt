package RplusMgmt::Controller::API::Realty;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Object::Realty;
use Rplus::Object::Realty::Manager;
use Rplus::Object::Query;
use Rplus::Object::Query::Manager;

use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Tag;
use Rplus::Model::Tag::Manager;
use Rplus::Model::MassMedia;
use Rplus::Model::MassMedia::Manager;
use Rplus::Model::Sublandmark;
use Rplus::Model::Sublandmark::Manager;
use Rplus::Model::Kladr;
use Rplus::Model::Kladr::Manager;
use Rplus::Model::Street;
use Rplus::Model::Street::Manager;
use Rplus::Model::MapHouse;
use Rplus::Model::MapHouse::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;

use Rplus::Config::Realty;
use Rplus::Util qw(format_phone_num format_house_num format_location);
use Rplus::Util::Realty qw(find_duplicate_realty);

use Rplus::DB;

use JSON;
use Encode qw(encode_utf8 decode_utf8);
use List::MoreUtils qw(none);

my %REALTY_TYPES_H = @Rplus::Config::Realty::REALTY_TYPES;
my %REALTY_OFFER_TYPES_H = @Rplus::Config::Realty::REALTY_OFFER_TYPES;
my %REALTY_STATES_H = @Rplus::Config::Realty::REALTY_STATES;

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'realty'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my @rdb_query;
    if (my $query_params = $self->param('query')) {
        eval {
            $query_params = decode_json($query_params);
            if (%$query_params) {
                $query_params->{'options'} = {
                    profile => scalar($self->param('profile')),
                    skip_description => 1,
                };
                @rdb_query = Rplus::Object::Query->new(params => $query_params)->build_rose_db_query;
            }
            1;
        } or do {
            say $@;
        };
    }

    if (my $filter = $self->param('filter')) {
        eval {
            $filter = decode_json($filter);
            if ($filter->{'state'} && ref($filter->{'state'}) eq 'ARRAY' && @{$filter->{'state'}}) {
                push @rdb_query, state => $filter->{'state'};
            }
            if ($filter->{'custom'} && ref($filter->{'custom'}) eq 'ARRAY') {
                for my $x (@{$filter->{'custom'}}) {
                    push @rdb_query, \"t1.id IN (SELECT CLAIMS.realty_id FROM claims WHERE CLAIMS.status = 'new') AND t1.close_date IS NULL";
                }
            }
            if ($filter->{'agent'} && $filter->{'agent'} =~ /^(all)|(nobody)|(\d+)$/ ) {
                push @rdb_query, '!agent_id' => undef if $filter->{'agent'} eq 'all';
                push @rdb_query, agent_id => undef if $filter->{'agent'} eq 'nobody';
                push @rdb_query, agent_id => $filter->{'agent'} if $filter->{'agent'} =~ /^\d+$/;
            }
            1;
        } or do {
            say $@;
        };
    }
    #push @rdb_query, state => 'work' if none { $_ eq 'state' } @rdb_query;;

    my $sort_by = 'open_date DESC';
    if (my $sort = $self->param('sort')) {
        eval {
            $sort = decode_json($sort);
            if ($sort->{'field'}) {
                my $dir = $sort->{'direction'} =~ /^desc$/i ? 'DESC' : 'ASC';
                if (
                    $sort->{'field'} eq 'realty_type' ||
                    $sort->{'field'} eq 'ap_scheme_id' ||
                    $sort->{'field'} eq 'rooms_count' ||
                    $sort->{'field'} eq 'price' ||
                    $sort->{'field'} eq 'floor' ||
                    $sort->{'field'} eq 'open_date' ||
                    $sort->{'field'} eq 'agent.name'
                ) {
                    $sort_by = $sort->{'field'}.' '.$dir;
                } elsif ($sort->{'field'} eq 'address') {
                    # FIXME: Bug in Rose::DB::Object (must be street.parent_kladr.name2)
                    $sort_by = 'parent_kladr.name2 '.$dir.', street.name2 '.$dir;
                }
            }
        }
    }

    my $per_page = $self->param('per_page') || 10;
    my $page = $self->param('page'); $page = 1 unless $page && $page > 0;

    my $res = {
        count => Rplus::Object::Realty::Manager->get_objects_count(query => \@rdb_query),
        list => [],
    };

    $page = int($res->{'count'} / $per_page) + ($res->{'count'} % $per_page) if ($page - 1) * $per_page >= $res->{'count'};
    $page = 1 if $page == 0;

    my $realty_iter = Rplus::Object::Realty::Manager->get_objects_iterator(
        query => \@rdb_query,
        ($sort_by ? (sort_by => $sort_by) : ()),
        with_objects => [ (map { $_->name } Rplus::Object::Realty->meta->foreign_keys), 'street.parent_kladr' ],
        #with_all_objects => 1,
        per_page => $per_page,
        page => $page,
    );
    while (my $realty = $realty_iter->next) {
        push @{$res->{'list'}}, {
            id => $realty->id,
            _state => $realty->state,
            realty_type => $REALTY_TYPES_H{$realty->realty_type},
            offer_type => $REALTY_OFFER_TYPES_H{$realty->offer_type},
            ap_scheme => $realty->ap_scheme_id ? $realty->ap_scheme->name : undef,
            rooms_count => $realty->rooms_count,
            address => format_location(street => $realty->street, house_num => $realty->house_num) || undef,
            price => $realty->price,
            floor_floors => $realty->floor ? $realty->floor.($realty->floors_count ? '/'.$realty->floors_count : '') : undef,
            seller_phones => $realty->seller_id ? [ map { format_phone_num($_, 'human') } ($realty->seller->contact_phones)[0..2] ] : undef,
            open_date => $realty->open_date->strftime('%d.%m.%Y'),
            agent_name => $realty->agent_id ? (scalar(split / /, $realty->agent->name) == 3 ? join(' ', (split / /, $realty->agent->name)[0,1]) : $realty->agent->name) : undef,
            tags => join(', ', map { $_->name } $realty->tags),
            source_mass_media => $realty->source_mass_media_id ? $realty->source_mass_media->name : undef,
            export_mass_media => join(', ', map { $_->name } $realty->export_mass_media),
            square => [
                ($realty->square_total ? join('/', $realty->square_total, ($realty->square_living || ()), ($realty->square_kitchen || ())).' кв.м.' : ()),
                ($realty->square_land ? $realty->square_land.(($realty->square_land_type || 'ar') eq 'ar' ? ' сот.' : ' га.') : ())
            ],
            main_photo_thumbnail => $realty->main_photo_id ? $self->url_for(sprintf("/photos/%s/%s", $realty->id, $realty->main_photo->thumbnail_filename)) : undef,
        };
    }

    # Навигация по страницам
    $res->{'page'} = $page;
    if ($res->{'count'}) {
        $res->{'prev'} = $page - 1 if $page > 1;
        $res->{'next'} = $page + 1 if $res->{'count'} > $page * $per_page;
    }

    $self->render_json($res);
}

my $_get_realty_data = sub {
    my $realty = shift;

    my @sublandmarks = @{Rplus::Model::Sublandmark::Manager->get_objects(
        query => [
            \("'{".join(',', $realty->__landmarks)."}' && t1.landmarks"),
            delete_date => undef,
        ],
    )} if @{$realty->__landmarks};

    return {
        %{$realty->as_tree(max_depth => 0)},

        title => format_location(street => $realty->street, house_num => $realty->house_num) || $REALTY_TYPES_H{$realty->realty_type},

        city_id => $realty->street_id ? $realty->street->parent_kladr_id : undef,
        street_id => $realty->street_id && !$realty->street->is_null ? $realty->street_id : undef,
        street => $realty->street_id && !$realty->street->is_null ? {id => $realty->street->id, text => $realty->street->name2} : undef,

        sublandmarks => [ map { {id => $_->id, text => $_->name} } @sublandmarks ],
        sublandmark => $realty->sublandmark_id ? {id => $realty->sublandmark->id, text => $realty->sublandmark->name} : undef,

        tags => scalar($realty->__tags),
        source_mass_media => $realty->source_mass_media_id ? $realty->source_mass_media->name : undef,
        export_mass_media => scalar($realty->__export_mass_media),

        seller => $realty->seller_id ? ({
            id => $realty->seller->id,
            name => $realty->seller->name,
            contact_phones => scalar($realty->seller->contact_phones),
        }) : undef,

        requirements => [],
    };
};

sub get {
    my $self = shift;

    my $id = $self->param('id');
    return $self->render_not_found unless $id;

    my $realty = Rplus::Object::Realty->new(id => $id)->load(speculative => 1);
    return $self->render_not_found unless $realty;

    $self->render_json($_get_realty_data->($realty));
}

sub create {
    my $self = shift;

    my $x = Rplus::DB->new_or_cached->dbh->selectrow_arrayref("SELECT nextval(?)", undef, "realty_id_seq");

    $self->render_json({id => $x->[0]});
}

sub set {
    my $self = shift;

    my $id = $self->param('id');
    my $state = $self->param('state');

    return $self->render_not_found unless $state;
    return $self->render_json({status => 'failed'}) unless $REALTY_STATES_H{$state};

    my $realty = Rplus::Object::Realty->new(id => $id)->load;
    if ($realty->state ne $state) {
        # Проверим на повтор (в рабочей базе)
        if ($state eq 'work') {
            if (my $duplicate_realty_id = find_duplicate_realty($_get_realty_data->($realty), ad_search => 1)) {
                my $duplicate_realty = Rplus::Object::Realty->new(id => $duplicate_realty_id)->load;
                return $self->render_json({status => 'duplicate', data => {id => $duplicate_realty->id, title => $duplicate_realty->get_digest('web_title')}});
            }
        }

        $realty->state($state);
        $realty->save(changes_only => 1);
    }

    return $self->render_json({status => 'success'});
}

sub save {
    my $self = shift;

    my $data; eval { $data = decode_json(encode_utf8(scalar($self->param('data')))); } or do {};
    return $self->render_json({status => 'failed'}) unless $data && ref($data) eq 'HASH' && $data->{'id'};

    #say $self->dumper(scalar($self->param('data')));
    #return $self->render_json({status => 'maintenance'});

    # Нормализация значений
    $data->{'house_num'} = format_house_num($data->{'house_num'}, 1) if $data->{'house_num'};
    $data->{'square_total'} =~ s/,/./ if $data->{'square_total'};
    $data->{'square_living'} =~ s/,/./ if $data->{'square_living'};
    $data->{'square_kitchen'} =~ s/,/./ if $data->{'square_kitchen'};
    $data->{'square_land'} =~ s/,/./ if $data->{'square_land'};
    $data->{'seller_price'} =~ s/,/./ if $data->{'seller_price'};
    $data->{'agency_price'} =~ s/,/./ if $data->{'agency_price'};
    $data->{'final_price'} =~ s/,/./ if $data->{'final_price'};

    # Валидация значений
    my @errors;
    {
        push @errors, {field => 'realty_type'} unless $data->{'realty_type'};
        push @errors, {field => 'offer_type'} unless $data->{'offer_type'};
        push @errors, {field => 'state'} unless $data->{'state'};

        if ($data->{'state'} eq 'work') {
            push @errors, {field => 'seller_price'} unless $data->{'seller_price'};

            my $t = $data->{'realty_type'};
            if ($t eq 'a') {
                push @errors, {field => 'rooms_count'} unless $data->{'rooms_count'};
                # Только для _новостроек_ не обязательно указание номера квартиры
                # Выключено 19.05.2013 (по желанию Дмитрия)
                #if (none { $_ == 30 } @{$data->{'tags'} || []}) {
                #    push @errors, {field => 'ap_num'} unless $data->{'ap_num'};
                #}
            }
            if ($t eq 'a' || $t eq 'r' || $t eq 'h' || $t eq 'c' || $t eq 'cr') {
                # Для городов указание улицы и номера дома обязательно всегда
                # Для остальных объектов - указание населённого пункта обязательно
                if ($data->{'city_id'}) {
                    my $kladr = Rplus::Model::Kladr->new(id => $data->{'city_id'})->load;
                    # Да, тут может быть эксепшен, если данные переданы неправильно
                    if ($kladr->level == 3) {
                        push @errors, {field => 'street_id'} unless $data->{'street_id'};
                        push @errors, {field => 'house_num'} unless $data->{'house_num'};
                    }
                } else {
                    push @errors, {field => 'city_id'};
                }
            }
        }
    }
    return $self->render_json({status => 'failed', errors => \@errors}) if @errors;

    # Проверим на повтор (в рабочей базе)
    if ($data->{'state'} eq 'work') {
        if (my $duplicate_realty_id = find_duplicate_realty($data, ad_search => 1)) {
            my $duplicate_realty = Rplus::Object::Realty->new(id => $duplicate_realty_id)->load;
            return $self->render_json({status => 'duplicate', data => {id => $duplicate_realty->id, title => $duplicate_realty->get_digest('web_title')}});
        }
    }

    # Начнём транзакцию
    my $db = Rplus::DB->new;
    $db->begin_work;

    my $realty = Rplus::Object::Realty->new(id => $data->{'id'}, db => $db);
    my $loaded = $realty->load(speculative => 1) ? 1 : 0;

    # Если переданные координаты не соответствуют предыдущим, сбросим географию недвижимости
    if (($data->{'latitude'}//0) != ($realty->latitude//0) || ($data->{'longitude'}//0) != ($realty->longitude//0)) {
        $realty->landmarks([]);
        $realty->sublandmarks([]);
        if ($data->{'latitude'} && $data->{'longitude'}) {
            $realty->latitude($data->{'latitude'});
            $realty->longitude($data->{'longitude'});
        } else {
            $realty->latitude(undef);
            $realty->longitude(undef);
        }
    }
    if (
        $data->{'street_id'} && $data->{'house_num'} &&
        ($data->{'street_id'} != ($realty->street_id//0) || $data->{'house_num'} ne ($realty->house_num//''))
    ) {
        my $map_house = Rplus::Model::MapHouse->new(street_id => $data->{'street_id'}, house_num => $data->{'house_num'})->load(speculative => 1);
        if ($map_house && $map_house->latitude == ($realty->latitude//0) && $map_house->longitude == ($realty->longitude//0)) {
            $realty->landmarks(scalar($map_house->landmarks));
            $realty->sublandmarks(scalar($map_house->sublandmarks));
            $realty->map_house_id($map_house->id);
        }
    }

    unless ($data->{'square_land'}) {
        delete $data->{'square_land_type'};
        $realty->square_land_type(undef);
    }

    for (@{$realty->meta->column_names}) {
        next if $_ eq 'id';
        next if /_date$/;
        next if $_ eq 'creator_id';
        next if $_ eq 'price';
        next if $_ eq 'landmarks';
        next if $_ eq 'sublandmarks';
        next if $_ eq 'requirements'; # Временно

        if ($_ eq 'tags') {
            # Проверим теги на актуальность
            my @tags = @{Rplus::Model::Tag::Manager->get_objects(query => [ id => $data->{$_}, delete_date => undef ])} if @{$data->{$_}};
            $realty->tags([map { $_->id } @tags]);
        } elsif ($_ eq 'export_mass_media') {
            my @mass_media = @{Rplus::Model::MassMedia::Manager->get_objects(query => [ id => $data->{$_} ])} if @{$data->{$_}};
            $realty->export_mass_media([map { $_->id } @mass_media]);
        } else {
            # Остальные поля доступны к изменению
            $realty->$_($data->{$_}) if exists $data->{$_};
        }
    }

    # Дополнительно, если указан город и не указана улица
    if ($data->{'city_id'} && !$data->{'street_id'}) {
        if (my $street = Rplus::Model::Street::Manager->get_objects(select => 'id', query => [ parent_kladr_id => $data->{'city_id'}, is_null => 1 ])->[0]) {
            $realty->street_id($street->id);
        } else {
            # Ерунда какая-то
        }
    }

    # Обновим информацию о покупателе
    my $seller;
    if (exists $data->{'seller'}) {
        if (my @seller_phones = map { format_phone_num($_) } @{$data->{'seller'}->{'contact_phones'}}) {
            if (my $seller_id = $data->{'seller'}->{'id'}) {
                $seller = Rplus::Model::Client->new(id => $seller_id, db => $db)->load;
            } else {
                $seller = Rplus::Model::Client->new(db => $db);
            }
            $seller->name($data->{'seller'}->{'name'} || undef);
            $seller->contact_phones(\@seller_phones);
        } else {
            $realty->seller_id(undef);
            return $self->render_json({status => 'failed', errors => [{field => 'seller'}]});
        }
    }

    eval {
        if ($seller) {
            $seller->save;
            $realty->seller_id($seller->id);
        }
        $realty->save($loaded ? (changes_only => 1) : (insert => 1));

        # Поставим время обновления объекта недвижимости
        Rplus::Object::Realty::Manager->update_objects(
            set => { change_date => \'now()' },
            where => [ id => $realty->id ],
            db => $db,
        );

        $db->commit;

        $realty->load;

        1;
    } or do {
        say $@;
        return $self->render_json({status => 'failed'});
    };

    my $is_mediator;
    if (!$realty->close_date) {
        my $mediator = Rplus::Model::Mediator::Manager->get_objects(
            query => [ phone_num => scalar($realty->seller->contact_phones), delete_date => undef ],
            require_objects => ['company'],
        )->[0];
        if ($mediator) {
            $is_mediator = {
                company => $mediator->company->name,
            };
        }
    }

    $self->render_json({
        status => 'success',
        data => {
            id => $realty->id,
            title => format_location(street => $realty->street, house_num => $realty->house_num) || $REALTY_TYPES_H{$realty->realty_type},
        },
        ($is_mediator ? (mediator => $is_mediator) : ()),
    });
}

1;
