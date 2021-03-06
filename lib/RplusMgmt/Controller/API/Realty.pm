package RplusMgmt::Controller::API::Realty;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Account::Manager;
use Rplus::Model::Realty::Manager;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::Media::Manager;
use Rplus::Model::Photo::Manager;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Option::Manager;

use Rplus::Util::PhoneNum;
use Rplus::Util::Query;
use Rplus::Util::Realty;
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::Task;
use Rplus::Util::Geo;
use Rplus::Util::Misc;
use Rplus::Util::History qw(realty_record get_object_changes);

use File::Path qw(make_path);
use POSIX qw(strftime);

use JSON;
use Mojo::Collection;
use Time::Piece;

use Data::Dumper;

no warnings 'experimental::smartmatch';

my %export_media;
my $media_iter = Rplus::Model::Media::Manager->get_objects_iterator(query => [type => 'export']);
while (my $media = $media_iter->next) {
    $export_media{$media->id} = $media->code;
}


my %accounts_hash;
my $accounts_iter = Rplus::Model::Account::Manager->get_objects_iterator(query => [del_date => undef],);
while (my $x = $accounts_iter->next) {
    $accounts_hash{$x->id} = $x->company_name ? $x->company_name : $x->name;
}

my $required_export_str = q|{
    "apartment": [
        "locality", "address", "house_num", "house_type_id", "ap_scheme_id",
        "rooms_count", "room_scheme_id",
        "floor", "floors_count", "condition_id", "balcony_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "apartment_new": [
        "locality", "address", "house_num", "house_type_id", "ap_scheme_id",
        "rooms_count", "room_scheme_id",
        "floor", "floors_count", "condition_id", "balcony_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "townhouse": [
        "locality", "address", "house_num", "house_type_id", "ap_scheme_id",
        "rooms_count", "room_scheme_id",
        "floor", "floors_count", "condition_id", "balcony_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "apartment_small": [
        "locality", "address", "house_num", "house_type_id", "ap_scheme_id",
        "rooms_count", "room_scheme_id",
        "floor", "floors_count", "condition_id", "balcony_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "room": [
        "locality", "address", "house_num", "house_type_id", "ap_scheme_id",
        "rooms_count", "rooms_offer_count", "room_scheme_id",
        "floor", "floors_count", "condition_id", "balcony_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "house": [
        "locality", "address", "house_num", "house_type_id",
        "rooms_count", "rooms_offer_count",
        "condition_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "cottage": [
        "locality", "address", "house_num", "house_type_id",
        "rooms_count", "rooms_offer_count",
        "condition_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "dacha": [
        "locality", "address", "house_num", "house_type_id",
        "rooms_count", "rooms_offer_count",
        "condition_id", "bathroom_id",
        "square_total",
        "description", "owner_price", "owner_phones"
    ],
    "land": [
        "locality", "address", "square_land", "square_land_type",
        "description", "owner_price",
        "owner_phones"
    ],
    "office_place": [
        "locality", "address", "house_num",
        "square_total",
        "description", "owner_price",
        "owner_phones"
    ],
    "warehouse_place": [
        "locality", "address", "house_num",
        "square_total", "floors_count",
        "description", "owner_price",
        "owner_phones"
    ],
    "garage": [
        "locality", "address", "description",
        "owner_price", "owner_phones"
    ],
    "other": [
        "locality", "address", "description",
        "owner_price", "owner_phones"
    ],
    "any": [
        "locality", "address", "description",
        "owner_price", "owner_phones"
    ]
}|;

my $required_export = from_json($required_export_str);

my $_make_copy = sub {
    my $self = shift;
    my $realty = shift;

    my $acc_id = $self->session('account')->{id};

    my $new_record;
    # Begin transaction
    my $db = $self->db;
    $db->begin_work;
    eval {
        #$realty->geocoords(undef);
        my $x = {
            (map { $_ => scalar($realty->$_) } $realty->meta->column_names),
        };
        delete $x->{geocoords};
        $new_record = Rplus::Model::Realty->new(%{$x}, db => $db);

        $new_record->id(undef);
        $new_record->account_id($acc_id);
        $new_record->hidden_for(undef);
        $new_record->save;

        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef]);
        while (my $photo = $photo_iter->next) {
            my $new_photo = Rplus::Model::Photo->new(db => $db);
            $new_photo->realty_id($new_record->id);
            $new_photo->filename($photo->filename);
            $new_photo->thumbnail_filename($photo->thumbnail_filename);
            $new_photo->save;
        }

        Rplus::Model::SubscriptionRealty::Manager->update_objects(
            set => {realty_id => $new_record->id},
            where => [realty_id => $realty->id],
            db => $db
        );

        my $hidden_for = Mojo::Collection->new(@{$realty->hidden_for});
        push @$hidden_for, ($acc_id);
        $realty->hidden_for($hidden_for->compact->uniq);
        $realty->save(changes_only => 1);
    } or do {
        $db->rollback;
        return undef;
    };
    $db->commit;

    return $new_record;
};

# Private function: serialize realty object(s)
my $_serialize = sub {
    my $self = shift;
    my @realty_objs = (ref($_[0]) eq 'ARRAY' ? @{shift()} : shift);
    my %params = @_;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my @exclude_fields = qw(ap_num source_media_id source_media_text owner_phones work_info reference source_url);

    my (@serialized, %realty_h);
    for my $realty (@realty_objs) {
        my $anothers_obj = 0;
        my $company = '';
        if ($realty->account_id && $realty->account_id != $acc_id) {
            $anothers_obj = 1;
            $company = $accounts_hash{$realty->account_id};
        } else {
            my $a = $realty->owner_phones;
            if (scalar @{$a}) {
                my $x = Rplus::Model::Mediator::Manager->get_objects(
                    query => [
                        phone_num => [@{$a}],
                        delete_date => undef,
                        or => [account_id => undef, account_id => $acc_id],
                        \("NOT t1.hidden_for_aid && '{".$acc_id."}'"),
                    ],
                    require_objects => ['company'],
                    limit => 1,
                )->[0];
                if ($x) {
                    $company = $x->company->name;
                }
            }
        }

        my $x = {
            (map { $_ => ($_ =~ /_date$/ ? $self->format_datetime($realty->$_) : scalar($realty->$_)) } grep { !($_ ~~ [qw(delete_date geocoords landmarks sublandmark_id address_object_id metadata fts fts_vector)]) } $realty->meta->column_names),

            main_photo_thumbnail => undef,
            color_tag_id => undef,
            mediator_company => $company,
            source_url => $realty->source_url,
        };

        if ($realty->color_tag) {
            my $ct = Mojo::Collection->new(@{$realty->color_tag});
            my $tag_prefix = $user_id . '_';
            $ct = $ct->grep(sub {
                $_ =~ /$tag_prefix/;
            });
            my $t = $ct->first;
            if ($t) {
                $t =~ s/^\d+?_//;
                $x->{color_tag_id} = $t;
            }
        }

        # Exclude fields for read permission "2"
        if ($anothers_obj || ($self->has_permission(realty => read => $realty->agent_id) == 2 && !($realty->agent_id ~~ @{$self->stash('user')->{subordinate}}))) {
            $x->{$_} = undef for @exclude_fields;
            $x->{export_media} = [];
            if ($realty->agent_id) {
                my $user = Rplus::Model::User::Manager->get_objects(query => [id => $realty->agent_id, delete_date => undef])->[0];
                $x->{owner_phones} = [$user->public_phone_num];
            }
        }

        # if it's a demo acc - hide refs and phones
        if ($self->account_type() eq 'demo') {
            $x->{reference} = '';
            $x->{owner_phones} = ['ДЕМО ВЕРСИЯ'];
        }

        push @serialized, $x;
        $realty_h{$realty->id} = $x;
    }

    # Fetch photos
    if (keys %realty_h) {
        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [keys %realty_h], delete_date => undef], sort_by => 'is_main DESC, id ASC');
        while (my $photo = $photo_iter->next) {
            next if $realty_h{$photo->realty_id}->{main_photo_thumbnail};
            $realty_h{$photo->realty_id}->{main_photo_thumbnail} = $self->config->{'storage'}->{'url'}.'/photos/'.$photo->thumbnail_filename;
        }
    }

    return @realty_objs == 1 ? $serialized[0] : @serialized;
};

sub list {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'read');

    # Input validation
    $self->validation->optional('agent_id')->like(qr/^(?:\d+|any|all|not_med|med|nobody|a\d+)$/);
    $self->validation->optional('page')->like(qr/^\d+$/);
    $self->validation->optional('per_page')->like(qr/^\d+$/);

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {agent_id => 'Invalid value'} if $self->validation->has_error('agent_id');
        push @errors, {page => 'Invalid value'} if $self->validation->has_error('page');
        push @errors, {per_page => 'Invalid value'} if $self->validation->has_error('per_page');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Input params
    my $q = $self->param_n('q');
    my $search_area = $self->param('search_area');

    my $state_code = $self->param('state_code') || 'any';
    my $offer_type_code = $self->param('offer_type_code') || 'any';
    my $rent_type = $self->param('rent_type') || 'any';

    my $agent_id = $self->param('agent_id') || 'any';
    my $sort_by = $self->param('sort_by');
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 30;

    my $depth = $self->param("depth") || 'full';

    my $color_tag_id = $self->param("color_tag_id") || 'any';

    my $rq_id = $self->param("rq_id") || 42;
    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $multy = 0;
    if ($state_code eq 'multy') {
        $multy = 1;
        $state_code = 'any';
    }

    # "where" query
    my @query;
    my $near_q;
    {
        if ($q && $q =~ s/(рядом )(.+)/ /i) {
            $near_q = $2;
        }

        my @types;
        if (1 != 2) {
            my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
            my $opt = from_json($options->{options});
            my $import = $opt->{import};

            my $mode = $self->session('account')->{mode};

            eval {
                while (my ($key, $value) = each %{$import}) {

                    if ($mode eq 'rent') {
                        next if $key !~ /rent/;
                    } elsif ($mode eq 'sale') {
                        next if $key !~ /sale/;
                    } else {

                    }

                    if ($key =~ /$offer_type_code-(\w+)/ && ($value eq 'true' || $value eq '1')) {
                        push @types, $1;
                    }
                }
                if (scalar @types) {
                    push @query, 'type_code' => \@types ;
                } else {
                    push @query, 'type_code' => 'none';
                }
            } or do {}
        }

        if ($depth ne 'full') {
            push @query, \("t1.last_seen_date > now() - interval '$depth days'");
        }

        if ($color_tag_id ne 'any') {
            my $tag = $user_id . '_' . $color_tag_id;
            push @query, \("t1.color_tag && '{$tag}'");
        }

        if ($state_code ne 'any') { push @query, state_code => $state_code } else { push @query, '!state_code' => 'deleted' };
        if ($offer_type_code ne 'any') {
            push @query, offer_type_code => $offer_type_code;
        };

        if ($offer_type_code eq 'rent' && $rent_type ne 'any') {
            push @query, rent_type => $rent_type;
        }

        my $agent_ok;
        if ($agent_id eq 'all' && $self->has_permission(realty => 'read')->{others}) {
            push @query, and => ['!agent_id' => undef, '!agent_id' => 10000];
            $agent_ok = 1;
        } elsif ($agent_id eq 'not_med') {
            push @query, agent_id => undef;
            push @query,
                [\"NOT EXISTS (SELECT 1 FROM mediators WHERE mediators.phone_num = ANY (t1.owner_phones) AND mediators.delete_date IS NULL AND (NOT mediators.hidden_for_aid && '{$acc_id}' AND (mediators.account_id IS NULL OR mediators.account_id = $acc_id)) LIMIT 1)"];
            $agent_ok = 1;
        } elsif ($agent_id eq 'med') {
            push @query,
                [\"EXISTS (SELECT 1 FROM mediators WHERE mediators.phone_num = ANY (t1.owner_phones) AND mediators.delete_date IS NULL AND (NOT mediators.hidden_for_aid && '{$acc_id}' AND (mediators.account_id IS NULL OR mediators.account_id = $acc_id)) LIMIT 1)"];
            $agent_ok = 1;
        } elsif ($agent_id =~ /^a(\d+)$/) {
            my $manager = Rplus::Model::User::Manager->get_objects(query => [id => $1, delete_date => undef])->[0];
            if (scalar (@{$manager->subordinate})) {
                push @query, agent_id => [$manager->subordinate];
            } else {
                push @query, agent_id => 0;
            }
            $agent_ok = 1;

        } elsif ($agent_id =~ /^\d+$/ && $self->has_permission(realty => read => $agent_id)) {
            push @query, agent_id => $agent_id;
            $agent_ok = 1;
        }
        if (!$agent_ok) {
            if ($self->has_permission(realty => 'read')->{nobody} && $self->has_permission(realty => 'read')->{others}) {
                # Ok, give access to all objects
            } elsif ($self->has_permission(realty => 'read')->{nobody}) {
                push @query, or => [
                    agent_id => $self->stash('user')->{id},
                    agent_id => undef,
                ];
            } elsif ($self->has_permission(realty => 'read')->{others}) {
                push @query, '!agent_id' => undef;
            } else {
                push @query, agent_id => $self->stash('user')->{id};
            }
        }

        if ($search_area) {
          push @query, \("postgis.st_covers(postgis.ST_GeomFromEWKT('SRID=4326;" . $search_area . "')::postgis.geography, t1.geocoords)");
        }
    }

    my (@sort_by, @with_objects);
    if  ($sort_by && $sort_by =~ /^(\w+)(\.\w+)?(?: (asc|desc))?$/) {
      push @with_objects, $1 if $1 && $2;
      push @sort_by, $sort_by;
    }

    if  ($sort_by) {
      #push @with_objects, $1 if $1 && $2;
      push @sort_by, $sort_by;
    }

    # Recognize phone numbers from query
    my @owner_phones;
    if ($q) {
        for my $x (split /[ .,]/, $q) {
            if ($x =~ /^\s*[0-9-]{6,}\s*$/) {
                if (my $phone_num = $self->parse_phone_num($x)) {
                    push @owner_phones, $phone_num;
                    $q =~ s/$x//;
                }
            }
        }
        push @query, \("t1.owner_phones && '{".join(',', map { '"'.$_.'"' } @owner_phones)."}'") if @owner_phones;
    }

    if ($multy) {
        push @query, multylisting => 1;
    } else {
        push @query, or => [account_id => undef, account_id => $acc_id];
        push @query, \("NOT hidden_for && '{".$acc_id."}'");
    }

    # Parse query
    push @query, Rplus::Util::Query::parse($q);

    if ($near_q) {
        push @query, Rplus::Util::Query::get_near_filter($near_q, $self);
    }

    my $res = {
        count => Rplus::Model::Realty::Manager->get_objects_count(
            query => [
                @query,
                delete_date => undef
            ],
            with_objects => [@with_objects]
        ),
        list => [],
        page => $page,
        rq_id => $rq_id,
        Rplus::Util::Misc::generate_code() => 0,   # wtf, что-то кэширует ответы!? >_<
    };

    # Additionaly check found phones for mediators
    if (@owner_phones) {
        my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(
            query => [
                phone_num => \@owner_phones,
                delete_date => undef,
                or => [account_id => undef, account_id => $acc_id],
                \("NOT t1.hidden_for_aid && '{".$acc_id."}'"),
            ],
            require_objects => ['company']
        );
        while (my $mediator = $mediator_iter->next) {
            push @{$res->{'mediators'}}, {id => $mediator->id, company => $mediator->company->name, phone_num => $mediator->phone_num};
        }
    }

    # Fetch realty objects
    my $realty_objs = Rplus::Model::Realty::Manager->get_objects(
        select => ['realty.*'],
        query => [
            @query,
            delete_date => undef,
        ],
        sort_by => [@sort_by, 'realty.last_seen_date desc'],
        page => $page,
        per_page => $per_page,
        with_objects => [@with_objects],
    );

    $res->{list} = [$_serialize->($self, $realty_objs)];

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'read');
    my $id = $self->param('id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => read => $realty->agent_id);

    unless ($realty->latitude) {
        if ($realty->address && $realty->house_num) {
            my %coords = Rplus::Util::Geo::get_coords_by_addr($realty->locality, $realty->address, $realty->house_num);
            if (%coords) {
                $realty->latitude($coords{latitude});
                $realty->longitude($coords{longitude});
                $realty->save(changes_only => 1);
            }
        }
    }
    my $res = $_serialize->($self, $realty);

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    # Input validation
    $self->validation->required('type_code'); # TODO: check value
    $self->validation->required('offer_type_code')->in(qw(sale rent));
    $self->validation->required('state_code'); # TODO: check value
    $self->validation->optional('house_type_id')->like(qr/^\d+$/);
    $self->validation->optional('ap_num')->like(qr/^\d+$/);
    $self->validation->optional('ap_scheme_id')->like(qr/^\d+$/);
    $self->validation->optional('rooms_count')->like(qr/^\d+$/);
    $self->validation->optional('rooms_offer_count')->like(qr/^\d+$/);
    $self->validation->optional('room_scheme_id')->like(qr/^\d+$/);
    $self->validation->optional('floor')->like(qr/^\d+$/);
    $self->validation->optional('floors_count')->like(qr/^\d+$/);
    $self->validation->optional('levels_count')->like(qr/^\d+$/);
    $self->validation->optional('condition_id')->like(qr/^\d+$/);
    $self->validation->optional('balcony_id')->like(qr/^\d+$/);
    $self->validation->optional('bathroom_id')->like(qr/^\d+$/);
    $self->validation->optional('square_total')->like(qr/^\d+(?:(?:\.|,)\d+)?$/);
    $self->validation->optional('square_living')->like(qr/^\d+(?:(?:\.|,)\d+)?$/);
    $self->validation->optional('square_kitchen')->like(qr/^\d+(?:(?:\.|,)\d+)?$/);
    $self->validation->optional('square_land')->like(qr/^\d+(?:(?:\.|,)\d+)?$/);
    $self->validation->optional('square_land_type')->in(qw/ar hectare/);
    $self->validation->optional('owner_price')->like(qr/^\d+(?:(?:\.|,)\d+)?$/);
    $self->validation->optional('agent_id')->like(qr/^\d+$/);
    $self->validation->optional('agency_price')->like(qr/^\d+(?:(?:\.|,)\d+)?$/);
    $self->validation->optional('latitude')->like(qr/^\d+\.\d+$/);
    $self->validation->optional('longitude')->like(qr/^\d+\.\d+$/);

    # Fields to save
    my @fields = (
        'type_code', 'offer_type_code', 'state_code',
        'house_type_id', 'ap_num', 'ap_scheme_id',
        'rooms_count', 'rooms_offer_count', 'room_scheme_id',
        'floor', 'floors_count', 'levels_count', 'condition_id', 'balcony_id', 'bathroom_id',
        'square_total', 'square_living', 'square_kitchen', 'square_land', 'square_land_type',
        'description', 'owner_info', 'owner_price', 'work_info', 'agent_id', 'agency_price',
        'latitude', 'longitude', 'multylisting', 'mls_price', 'mls_price_type',
        'rent_type', 'lease_deposite_id', 'locality', 'address', 'house_num', 'district', 'poi'
    );

    my @fields_array = ('owner_phones', 'export_media');

    my @errors;
    if ($self->validation->has_error) {
        for (@fields) {
            push @errors, {$_ => 'Invalid value'} if $self->validation->has_error($_);
        }
    }

    # Prepare data
    my $color_tag_id = $self->param('color_tag_id');
    my %data;
    for (@fields) {
        $data{$_} = $self->param_n($_);
        $data{$_} =~ s/,/./ if $data{$_} && $_ =~ /^square_/;
        $data{$_} =~ s/,/./ if $data{$_} && $_ =~ /_price$/;
    }

    # attachments
    $data{attachments} = Mojo::Collection->new(@{$self->every_param('attachments[]')})->compact->uniq;

    # Owner phones
    $data{owner_phones} = Mojo::Collection->new(@{$self->every_param('owner_phones[]')})->map(sub { $self->parse_phone_num($_) })->compact->uniq;
    push @errors, {owner_phones => 'Empty phones'} unless @{$data{owner_phones}};

    my $realty;
    if (my $id = $self->param('id')) {
        $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
    } else {
        $realty = Rplus::Model::Realty->new(
            creator_id => $user_id,
            agent_id => scalar $self->param('agent_id'),
            account_id => $acc_id,
        );
    }
    # Check for errors & check that we can rewrite agent
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {errors => \@errors}, status => 400) if @errors;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $self->param_n('agent_id'));

    # Export media
    my $export_media_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT M.id, M.name FROM media M WHERE M.type = 'export' AND M.delete_date IS NULL}, 'id');
    $data{export_media} = Mojo::Collection->new(@{$self->every_param('export_media[]')})->grep(sub { exists $export_media_ok->{$_} })->uniq;

    # Color tag
    my $ct = Mojo::Collection->new();
    if ($realty->color_tag) {
        $ct = Mojo::Collection->new(@{$realty->color_tag});
    }
    my $tag_prefix = $user_id . '_';
    if ($color_tag_id) {        # add tag
        $ct = $ct->grep(sub {   # remove all user tags
            $_ !~ /$tag_prefix/;
        });
        my $tag = $user_id . '_' . $color_tag_id;
        push @$ct, $tag;        # add new
    } else {                    # remove tag
        $ct = $ct->grep(sub {
            $_ !~ /$tag_prefix/;
        });
    }
    $realty->color_tag($ct->uniq);

    unless ($realty->account_id) {
        $realty = $_make_copy->($self, $realty);
        return $self->render(json => {error => 'Unable to make a copy'}, status => 404) unless $realty;
    }

    # if agent_id changed - set 'assign_date'
    $realty->assign_date('now()') if $realty->agent_id != $data{agent_id};

    if ($realty->id) {
        realty_record($acc_id, $user_id, 'update', $realty, \%data);
        if (get_object_changes($realty, \%data)) {    # something changed
            $realty->change_date('now()');
        }
    }

    # Save data
    $realty->$_($data{$_}) for keys %data;

    eval {
        if ($realty->id) {
            $realty->save(changes_only => 1);
        } else {
            $realty->save(insert => 1);
            realty_record($acc_id, $user_id, 'add', $realty, undef);
        }
        1;
    } or do {
        return $self->render(json => {error => $@}, status => 500) unless $realty;
    };

    $realty->load;

    my $res = {
        status => 'success',
        id => $realty->id,
        realty => $_serialize->($self, $realty),
        #similar_realty_id => $similar_realty_id,
        #($similar_realty ? (similar_realty => $_serialize->($self, $similar_realty)) : ()),
    };

    $self->render(json => $res);
}

sub set_color_tag_multiple {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $color_tag_id = $self->param('color_tag_id');
    my $ids = Mojo::Collection->new(@{$self->every_param('id[]')});

    my %realtys;
    my @errors;

    $ids->each(sub {
        my ($id, $idx) = @_;
        my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
        unless ($realty) {
            push @errors, $id;
            return;
        }

        my $ct = Mojo::Collection->new();
        if ($realty->color_tag) {
            $ct = Mojo::Collection->new(@{$realty->color_tag});
        }
        my $tag_prefix = $user_id . '_';
        my $tag = $tag_prefix . $color_tag_id;
        if ($ct->first(qr/$tag/)) {   # remove tag
            $ct = $ct->grep(sub {
                $_ !~ /$tag/;
            });
        } else {                       # add tag
            $ct = $ct->grep(sub {
                $_ !~ /$tag_prefix/;
            });
            push @$ct, $tag;
        }
        $realty->color_tag($ct->uniq);
        $realty->save(changes_only => 1);

        $realtys{$realty->id} = $_serialize->($self, $realty);
    });

    my $res = {
        status => 'success',
        list => {%realtys},
        errors => [@errors],
    };

    return $self->render(json => $res);
}

sub update_multiple {
    my $self = shift;

    # Increase inactivity timeout for connection a bit
    Mojo::IOLoop->stream($self->tx->connection)->timeout(1200);
    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $ids = Mojo::Collection->new(@{$self->every_param('id[]')});

    my $agent_id = $self->param('agent_id');
    my $export_media = $self->param('export_media');
    my $state_code = $self->param('state_code');

    my %realtys;
    my @errors;


    $ids->each(sub {
        my ($id, $idx) = @_;

        my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
        unless ($realty) {
            push @errors, $id;
            return;
        }
        my $old_id = $realty->id;

        unless ($realty->account_id) {
            $realty = $_make_copy->($self, $realty);
            unless ($realty) {
                push @errors, $id;
                return;
            }
        }

        if (defined $agent_id) {
            unless ($self->has_permission(realty => write => $realty->agent_id)) {
                unless ($self->has_permission(realty => 'write')->{can_assign} && $agent_id == $user_id) {
                    push @errors, $id;
                    return;
                }
            }

            if ($agent_id == 10000) {
                add_mediator('ПОСРЕДНИК В НЕДВИЖИМОСТИ', $realty->owner_phones->[0], 'user_' . $user_id, $acc_id);
            } else {
                realty_record($acc_id, $user_id, 'update', $realty, {
                    agent_id => $agent_id
                });
                if ($agent_id) {
                    $realty->agent_id($agent_id);
                } else {
                    $realty->agent_id(undef);
                }
                $realty->assign_date('now()');
            }
        }

        if ($export_media) {
            my $export_media_id = $self->param_n('export_media');
            my $export_media_ok = Rplus::DB->new_or_cached->dbh->selectall_arrayref(q{SELECT M.id, M.name FROM media M WHERE M.type = 'export' AND M.delete_date IS NULL});

            unless ($self->has_permission(realty => write => $realty->agent_id) || !exists $export_media_ok->{$export_media_id}) {
                push @errors, $id;
                return;
            }

            unless ($export_media_id ~~ @{$realty->export_media}) {
                my $req_fields;
                if ($required_export->{$realty->type_code}) {
                    $req_fields = $required_export->{$realty->type_code};
                } else {
                    $req_fields = $required_export->{'any'};
                }
                if ($req_fields) {
                    foreach (@$req_fields) {
                        unless ($realty->$_) {
                            push @errors, $id;
                            return;
                        }
                    }
                }
            }

            my $new_export_media;
            if ($export_media_id ~~ @{$realty->export_media}) {
                $new_export_media = Mojo::Collection->new(grep { $_ != $export_media_id } @{$realty->export_media});
            } else {
                $new_export_media = Mojo::Collection->new(@{$realty->export_media});
                push @$new_export_media, ($export_media_id);
            }

            realty_record($acc_id, $user_id, 'update', $realty, {
                export_media => $new_export_media
            });
            $realty->export_media($new_export_media->compact->uniq);
        }

        if ($state_code) {
            unless ($self->has_permission(realty => write => $realty->agent_id)) {
                push @errors, $id;
                return;
            }
            my $new_state_code = $self->param('state_code');
            realty_record($acc_id, $user_id, 'update', $realty, {
                state_code => $new_state_code
            });
            $realty->state_code($new_state_code);
        }

        # Save data
        eval {
            $realty->change_date('now()');
            $realty->save(changes_only => 1);
            1;
        } or do {
            unless ($realty) {
                push @errors, $id;
                return;
            }
        };

        $realty->load;

        $realtys{$old_id} = $_serialize->($self, $realty);
    });

    my $res = {
        status => 'success',
        list => {%realtys},
        errors => [@errors],
    };

    return $self->render(json => $res);
}

sub like_it {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $id = $self->param('id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
    return $self->render(json => {error => 'Not found'}, status => 404) unless $realty;

    realty_record($acc_id, $user_id, 'like_it', $realty, undef);

    $realty->like_it($realty->like_it + 1);
    $realty->save(changes_only => 1);

    return $self->render(json => {status => 'success'});
}

sub get_location {
    my $self = shift;

    my $locality = $self->param('locality');
    my $address = $self->param('address');
    my $house_num = $self->param('house_num');

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my %coords;
    my $district = '';
    my $pois = [];

    if ($address) {
        %coords = Rplus::Util::Geo::get_coords_by_addr($locality, $address, $house_num);
    }

    if ($coords{latitude}) {
      my $location_meta = Rplus::Util::Geo::get_location_metadata($coords{latitude}, $coords{longitude}, $self->config);

      $district = join ', ', @{$location_meta->{district}};
      $pois = $location_meta->{pois};
    }

    return $self->render(json => {status => 'success', latitude => $coords{latitude}, longitude => $coords{longitude}, district => $district, pois => $pois});
}

sub update_location {
    my $self = shift;

    my $id = $self->param('id');
    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;

    if ($realty->address) {
        my %coords = Rplus::Util::Geo::get_coords_by_addr($realty->locality, $realty->address, $realty->house_num);

        if (%coords) {
            $realty->latitude($coords{latitude});
            $realty->longitude($coords{longitude});
            $realty->save(changes_only => 1);
        }
    }

    if ($realty->latitude) {
       my $res = Rplus::Util::Geo::get_location_metadata($realty->latitude, $realty->longitude, $self->config);

       $realty->district(join ', ', @{$res->{district}});
       $realty->pois($res->{pois});
       $realty->save(changes_only => 1);
    }

    if ($realty->latitude) {
        return $self->render(json => {
          status => 'success',
          lat => $realty->latitude,
          lng => $realty->longitude,
          district => $realty->district,
          pois => $realty->pois
        });
    } else {
        return $self->render(json => {status => 'not_found'});
    }
}

sub upload_file {
    my $self = shift;

    my $file_url = '';
    my $cat = '/users/files/';

    if (my $file = $self->param('file')) {
        my $ts = (Time::HiRes::time =~ s/\.//r);
        $cat .= $ts . '/';
        my $path = $self->config->{'storage'}->{'path'} . $cat;
        my $name = strftime('%d.%m %H:%M',localtime) . ' ' . $file->filename;

        eval {
            make_path($path);
            $file->move_to($path . $name);
            $file_url = $cat . $name;
        } or do {
            return $self->render(json => {error => $@}, status => 500);
        };

        return $self->render(json => {status => 'success', file_url => $self->config->{'storage'}->{'url'} . $file_url});
    }

    return $self->render(json => {error => 'Bad Request'}, status => 400);
}

1;
