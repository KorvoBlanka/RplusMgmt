package RplusMgmt::Controller::API::Realty;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::RealtyColorTag;
use Rplus::Model::RealtyColorTag::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use Rplus::Util::PhoneNum;
use Rplus::Util::Query;
use Rplus::Util::Realty;
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::Task;
use Rplus::Util::Geo;

use File::Path qw(make_path);
use POSIX qw(strftime);

use JSON;
use Mojo::Collection;
use Time::Piece;

use Data::Dumper;

no warnings 'experimental::smartmatch';

my %accounts_hash;
#my %mediators_hash;

my $accounts_iter = Rplus::Model::Account::Manager->get_objects_iterator(query => [del_date => undef],);
while (my $x = $accounts_iter->next) {
    $accounts_hash{$x->id} = $x->company_name ? $x->company_name : $x->name;
}

my $_make_copy = sub {
    my $self = shift;
    my $realty = shift;

    my $acc_id = $self->session('user')->{account_id};

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
        
        my $color_tag = Rplus::Model::RealtyColorTag::Manager->get_objects(query => [realty_id => $realty->id])->[0];
        if ($color_tag) {
            Rplus::Model::RealtyColorTag->new (
                realty_id => $new_record->id,
                tag0 => [$color_tag->tag0],
                tag1 => [$color_tag->tag1],
                tag2 => [$color_tag->tag2],
                tag3 => [$color_tag->tag3],
                tag4 => [$color_tag->tag4],
                tag5 => [$color_tag->tag5],
                tag6 => [$color_tag->tag6],
                tag7 => [$color_tag->tag7],
                db => $db
            )->save;
        }

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

    my $acc_id = $self->session('user')->{account_id};

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
        #elsif ($realty->mediator_realty) {
        #    my %mr_hash;
        #    foreach($realty->mediator_realty) {
        #        if ($_->account_id) {
        #            $mr_hash{$_->account_id} = $_->mediator_company->name;
        #        } else {
        #            $company = $_->mediator_company->name;
        #        }
        #    }
        #    if ($mr_hash{$acc_id}) {
        #        $company = $mr_hash{$acc_id};
        #    }
        #}

        my $x = {
            (map { $_ => ($_ =~ /_date$/ ? $self->format_datetime($realty->$_) : scalar($realty->$_)) } grep { !($_ ~~ [qw(delete_date geocoords landmarks metadata fts)]) } $realty->meta->column_names),

            address_object => $realty->address_object_id ? {
                id => $realty->address_object->id,
                name => $realty->address_object->name,
                short_type => $realty->address_object->short_type,
                expanded_name => $realty->address_object->expanded_name,
                addr_parts => from_json($realty->address_object->metadata)->{'addr_parts'},
            } : undef,

            sublandmark => $realty->sublandmark ? {id => $realty->sublandmark->id, name => $realty->sublandmark->name} : undef,
            main_photo_thumbnail => undef,
            color_tag_id => undef,            
            mediator_company => $company,
            source_url => $realty->source_url,
        };

        #if ($realty->color_tags) {
        #    foreach($realty->color_tags) {
        #        if ($_->{user_id} == $self->stash('user')->{id}) {
        #            $x->{color_tag_id} = $_->{color_tag_id};
        #            last;
        #        }
        #    }
        #}

        if ($realty->realty_color_tag) {
            for (my $i = 0; $i <= 7; $i ++) {
                my $tag_name = 'tag' . $i;
                if ($self->stash('user')->{id} ~~ @{$realty->realty_color_tag->$tag_name}) {
                    $x->{color_tag_id} = $i;
                    last;
                }
            }
        }
        
        # Exclude fields for read permission "2"
        if ($anothers_obj || ($realty->agent_id != 10000 && $self->has_permission(realty => read => $realty->agent_id) == 2 && !($realty->agent_id ~~ @{$self->stash('user')->{subordinate}}))) {
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

        if ($params{with_sublandmarks}) {
            if (@{$realty->landmarks} || $realty->sublandmark_id) {
                my $sublandmarks = Rplus::Model::Landmark::Manager->get_objects(
                    select => 'id, name',
                    query => [
                        id => [@{$realty->landmarks}, $realty->sublandmark_id || ()],
                        type => 'sublandmark',
                        delete_date => undef,
                    ],
                    sort_by => 'name',
                );
                $x->{sublandmarks} = [map { {id => $_->id, name => $_->name} } @$sublandmarks];
            } else {
                $x->{sublandmarks} = [];
            }
        }

        push @serialized, $x;
        $realty_h{$realty->id} = $x;
    }

    # Fetch photos
    if (keys %realty_h) {
        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [keys %realty_h], delete_date => undef], sort_by => 'is_main DESC, id ASC');
        while (my $photo = $photo_iter->next) {
            next if $realty_h{$photo->realty_id}->{main_photo_thumbnail};
            $realty_h{$photo->realty_id}->{main_photo_thumbnail} = $self->config->{'storage'}->{'url'}.'/photos/'.$photo->realty_id.'/'.$photo->thumbnail_filename;
        }
    }

    return @realty_objs == 1 ? $serialized[0] : @serialized;
};

sub list_for_plot {
    my $self = shift;
    
    my $q = $self->param_n('q');
    my $offer_type = $self->param_n('offer_type');
    my $from_date = $self->param('from_date');
    my $to_date = $self->param('to_date');
    my $object_count = $self->param('object_count');
    
    # "where" query
    my @query;
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

    # Parse query
    push @query, Rplus::Util::Query->parse($q, $self);

    my @date_range;
    unless ($from_date eq '') {
        push @date_range, add_date => {gt => $from_date};
    }

    unless ($to_date eq '') {
        push @date_range, add_date => {lt => $to_date};
    }
    
    my $res = {
        count => Rplus::Model::Realty::Manager->get_objects_count(query => [@query, @date_range, offer_type_code => $offer_type, '!price' => undef, delete_date => undef]),
        list => [],
    };
    
    # Fetch realty objects
    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
        select => ['realty.add_date', 'realty.price'],
        query => [@query, @date_range, offer_type_code => $offer_type, '!price' => undef, '!price' => 0, delete_date => undef],
        sort_by => ['realty.add_date desc'],
        page => 1,
        per_page => $object_count,
    );
    
    while (my $realty = $realty_iter->next) {
        my $x = {
            add_date => $realty->add_date,
            cost => $realty->price,
        };
        push @{$res->{list}}, $x;
    }
    
    return $self->render(json => $res);
}

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
    my $state_code = $self->param('state_code') || 'any';
    my $offer_type_code = $self->param('offer_type_code') || 'any';
    my $rent_type = $self->param('rent_type') || 'any';
    
    my $agent_id = $self->param('agent_id') || 'any';
    my $sort_by = $self->param('sort_by');
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 30;
    my $color_tag_id = $self->param("color_tag_id") || 'any';

    my $rq_id = $self->param("rq_id") || 42;
    my $acc_id = $self->session('user')->{account_id};

    my $multy = 0;
    if ($state_code eq 'multy') {
        $multy = 1;
        $state_code = 'work';
    }

    # "where" query
    my @query;
    {
        my @types;
        if (1 != 2) {
            my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
            my $opt = from_json($options->{options});
            my $import = $opt->{import};
            
            my $mode = $self->session->{'user'}->{'mode'};
            
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
    
        if ($color_tag_id ne 'any') {
            push @query, and => [
                'realty_color_tags.tag' . $color_tag_id  => $self->stash('user')->{id},
            ];
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
                [\"NOT EXISTS (SELECT 1 FROM mediators WHERE mediators.phone_num = ANY (t1.owner_phones) AND mediators.delete_date IS NULL AND ((mediators.account_id IS NULL AND NOT mediators.hidden_for_aid && '{$acc_id}') OR mediators.account_id = $acc_id) LIMIT 1)"];
            $agent_ok = 1;
        } elsif ($agent_id eq 'med') {
            push @query,
                [\"EXISTS (SELECT 1 FROM mediators WHERE mediators.phone_num = ANY (t1.owner_phones) AND mediators.delete_date IS NULL AND ((mediators.account_id IS NULL AND NOT mediators.hidden_for_aid && '{$acc_id}') OR mediators.account_id = $acc_id) LIMIT 1)"];
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

    # Parse query
    push @query, Rplus::Util::Query->parse($q, $self);

    if ($multy) {
        push @query, multylisting => 1;
    } else {
        push @query, or => [account_id => undef, account_id => $acc_id];
        push @query, \("NOT hidden_for && '{".$acc_id."}'");
    }

    my $res = {
        count => Rplus::Model::Realty::Manager->get_objects_count(
            query => [
                @query,
                delete_date => undef
            ],
            with_objects => ['realty_color_tag', @with_objects]
        ),
        list => [],
        page => $page,
        rq_id => $rq_id,
    };

    # Delete FTS data if no objects found
    if (!$res->{count}) {
        @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } @query;
        $res->{count} = Rplus::Model::Realty::Manager->get_objects_count(
            query => [
                @query,
                delete_date => undef,
            ],
            with_objects => ['realty_color_tag', @with_objects]
        );
    }

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
        select => ['realty.*', (map { 'address_object.'.$_ } qw(id name short_type expanded_name metadata))],
        query => [
            @query,
            delete_date => undef,
        ],
        sort_by => [@sort_by, 'realty.last_seen_date desc'],
        page => $page,
        per_page => $per_page,
        with_objects => ['address_object', 'sublandmark', 'realty_color_tag', @with_objects],
        #with_objects => ['address_object', 'sublandmark', 'color_tags', 'mediator_company', 'mediator_realty', @with_objects],
    );
    
    $res->{list} = [$_serialize->($self, $realty_objs)];

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'read');
    my $id = $self->param('id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef], with_objects => ['address_object'])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => read => $realty->agent_id);
    
    unless ($realty->latitude) {
        if ($realty->address_object && $realty->house_num) {
            my %coords = Rplus::Util::Geo::get_coords_by_addr($realty->address_object, $realty->house_num);
            if (%coords) {
                $realty->latitude($coords{latitude});
                $realty->longitude($coords{longitude});
                $realty->save(changes_only => 1);
            }
        }
    }
    my $res = $_serialize->($self, $realty, with_sublandmarks => 1);

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');
    
    my $create_event = 0;

    my $acc_id = $self->session('user')->{account_id};

    # Input validation
    $self->validation->required('type_code'); # TODO: check value
    $self->validation->required('offer_type_code')->in(qw(sale rent));
    $self->validation->required('state_code'); # TODO: check value
    $self->validation->optional('address_object_id')->like(qr/^\d+$/);
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
    $self->validation->optional('sublandmark_id')->like(qr/^\d+$/);

    if ($self->param('state_code') eq 'work' && !$self->param('agent_id')) {
        return $self->render(json => {error => 'Forbidden'}, status => 403);
    }

    # Fields to save
    my @fields = (
        'type_code', 'offer_type_code', 'state_code',
        'address_object_id', 'house_num', 'house_type_id', 'ap_num', 'ap_scheme_id',
        'rooms_count', 'rooms_offer_count', 'room_scheme_id',
        'floor', 'floors_count', 'levels_count', 'condition_id', 'balcony_id', 'bathroom_id',
        'square_total', 'square_living', 'square_kitchen', 'square_land', 'square_land_type',
        'description', 'owner_info', 'owner_price', 'work_info', 'agent_id', 'agency_price',
        'latitude', 'longitude', 'sublandmark_id', 'multylisting', 'mls_price', 'mls_price_type',
        'rent_type',
    );

    my @fields_array = ('owner_phones', 'tags', 'export_media');

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
    $data{attachments} = Mojo::Collection->new($self->param('attachments[]'))->compact->uniq;
    
    # Owner phones
    $data{owner_phones} = Mojo::Collection->new($self->param('owner_phones[]'))->map(sub { $self->parse_phone_num($_) })->compact->uniq;
    push @errors, {owner_phones => 'Empty phones'} unless @{$data{owner_phones}};

    my $realty;
    if (my $id = $self->param('id')) {
        $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
    } else {
        $realty = Rplus::Model::Realty->new(
            creator_id => $self->stash('user')->{id},
            agent_id => scalar $self->param('agent_id'),
            account_id => $acc_id,
        );
    }
    # Check for errors & check that we can rewrite agent
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {errors => \@errors}, status => 400) if @errors;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $self->param_n('agent_id'));

    my $changed = 0;
    foreach (keys %data) {
        if ($realty->$_ ne $data{$_}) {
            $changed = 1;
            last;
        }
    }
    my $aref = $realty->owner_phones;
    if ($aref && $data{owner_phones}->size == scalar @$aref) {
        for (my $i = 0; $i < $data{owner_phones}->size; $i++) {
            if ($data{owner_phones}[$i] ne $realty->owner_phones->[$i]) {
                $changed = 1;
            }
        }
    }

    # Tags
    #my $tags_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT T.id, T.name FROM tags T WHERE T.delete_date IS NULL}, 'id');
    #$data{tags} = Mojo::Collection->new($self->param('tags[]'))->grep(sub { exists $tags_ok->{$_} })->uniq;

    # Export media
    my $export_media_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT M.id, M.name FROM media M WHERE M.type = 'export' AND M.delete_date IS NULL}, 'id');
    $data{export_media} = Mojo::Collection->new($self->param('export_media[]'))->grep(sub { exists $export_media_ok->{$_} })->uniq;

    if (!$realty->agent_id) {
        $realty->export_media(Mojo::Collection->new());
    }

    # Find similar realty
    #my $similar_realty_id = Rplus::Util::Realty->find_similar(%data, state_code => ['raw', 'work', 'suspended']);
    #my $similar_realty = Rplus::Model::Realty->new(id => $similar_realty_id)->load(with => ['address_object']) if $similar_realty_id;

    if ($data{agent_id}) {
        if ($realty->id) {
            if ($realty->agent_id != $data{agent_id}) {
                $create_event = 1;
            }
        } else {
            $create_event = 1;
        }
    }

    unless ($realty->account_id) {
        $realty = $_make_copy->($self, $realty);
        return $self->render(json => {error => 'Unable to make a copy'}, status => 404) unless $realty;
    }

    # if agent_id changed - set 'assign_date'
    $realty->assign_date('now()') if $realty->agent_id != $data{agent_id};

    # Save data
    $realty->$_($data{$_}) for keys %data;
    if ($changed) {
        $realty->change_date('now()');
    }

    if ($realty->state_code eq 'work' && !$realty->agent_id) {
        $realty->state_code('raw');
    }

    if (!$realty->agent_id) {
        $realty->export_media(Mojo::Collection->new());
    }
    
    # 
    my @mls_fields_apartment = (
        'address_object_id', 'house_num', 'house_type_id', 'ap_scheme_id',
        'rooms_count', 'room_scheme_id',
        'floor', 'floors_count', 'condition_id', 'balcony_id', 'bathroom_id',
        'square_total',
        'description', 'owner_price', 'agent_id', 'mls_price',
    );

    # 
    my @mls_fields_rooms = (
        'address_object_id', 'house_num', 'house_type_id', 'ap_scheme_id',
        'rooms_count', 'rooms_offer_count', 'room_scheme_id',
        'floor', 'floors_count', 'condition_id', 'balcony_id', 'bathroom_id',
        'square_total',
        'description', 'owner_price', 'agent_id', 'mls_price',
    );
    
    my @mls_fields_house = (
        'address_object_id', 'house_num', 'house_type_id',
        'rooms_count', 'rooms_offer_count',
        'condition_id', 'bathroom_id',
        'square_total',
        'description', 'owner_price', 'agent_id', 'mls_price',
    );
    
    # 
    my @mls_fields_land = (
        'square_land', 'square_land_type',
        'description', 'owner_price', 'agent_id',
        'mls_price',
    );

    # 
    my @mls_fields_office = (
        'address_object_id', 'house_num',
        'square_total',
        'description', 'owner_price', 'agent_id',
        'mls_price',
    );
    
    # 
    my @mls_fields_other = (
        'description', 'owner_price', 'agent_id',
        'mls_price',
    );
    
    my @mls_fields;
    
    if ($realty->type_code eq 'room') {
        @mls_fields = @mls_fields_rooms;
    } elsif ($realty->type_code eq 'apartment' || $realty->type_code eq 'apartment_small' || $realty->type_code eq 'apartment_new' || $realty->type_code eq 'townhouse') {
        @mls_fields = @mls_fields_apartment;
    } elsif ($realty->type_code eq 'house' || $realty->type_code eq 'cottage' || $realty->type_code eq 'dacha') {
        @mls_fields = @mls_fields_house;
    } elsif ($realty->type_code eq 'land') {
        @mls_fields = @mls_fields_land;
    } elsif ($realty->type_code eq 'office') {
        @mls_fields = @mls_fields_office;
    } elsif ($realty->type_code eq 'other') {
        @mls_fields = @mls_fields_other;
    }

    for (@mls_fields) {
        unless ($realty->$_) {
            $realty->multylisting(0);
            last;
        }        
    }
    
    if ($realty->state_code ne 'work') {
        $realty->multylisting(0);
    }

    eval {
        $realty->save($realty->id ? (changes_only => 1) : (insert => 1));
        1;
    } or do {
        return $self->render(json => {error => $@}, status => 500) unless $realty;
    };

    $realty->load;

    eval {
        my $user_id = $self->stash('user')->{id};
        my $realty_tag = Rplus::Model::RealtyColorTag::Manager->get_objects(query => [realty_id => $realty->id],)->[0];
        if (!$realty_tag) {
            $realty_tag = Rplus::Model::RealtyColorTag->new(realty_id => $realty->id);
        }
        for (my $i = 0; $i <= 7; $i ++) {
            my $tag_name = 'tag' . $i;
            my $t_tags = Mojo::Collection->new(grep { $_ != $self->stash('user')->{id} } @{$realty_tag->$tag_name});
            $realty_tag->$tag_name($t_tags->compact->uniq);
        }
        my $tag_name = 'tag' . $color_tag_id;
        my $t_tags = Mojo::Collection->new(@{$realty_tag->$tag_name});
        push @$t_tags, ($user_id);
        $realty_tag->$tag_name($t_tags->compact->uniq);
        $realty_tag->save;

        if ($create_event) {
            my $start_date = localtime;
            my $end_date = $start_date + 15 * 60;
            my $start_date_str = $start_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));
            my $end_date_str = $end_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));

            my @parts;
            {
                push @parts, $realty->type->name;
                push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                push @parts, $realty->price.' тыс. руб.' if $realty->price;
            }
            my $summary = join(', ', @parts);

            Rplus::Util::Task::qcreate($self, {
                    task_type_id => 9, # назначен объект
                    assigned_user_id => $realty->agent_id,
                    start_date => $start_date_str,
                    end_date => $end_date_str,
                    summary => $summary,
                    client_id => undef,
                    realty_id => $realty->id,
                });        
        }        
    };
    if ($@) {
        
    }

    my $res = {
        status => 'success',
        id => $realty->id,
        realty => $_serialize->($self, $realty),
        #similar_realty_id => $similar_realty_id,
        #($similar_realty ? (similar_realty => $_serialize->($self, $similar_realty)) : ()),
    };

    $self->render(json => $res);
}

sub set_color_tag {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};
    my $user_id = $self->stash('user')->{id};
    my $id = $self->param('id');
    my $color_tag_id = $self->param('color_tag_id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;

    my $realty_tag = Rplus::Model::RealtyColorTag::Manager->get_objects(query => [realty_id => $id],)->[0];
    if (!$realty_tag) {
        $realty_tag = Rplus::Model::RealtyColorTag->new(realty_id => $id);
    }

    for (my $i = 0; $i <= 7; $i ++) {
        my $tag_name = 'tag' . $i;
        if ($i == $color_tag_id) {
            if ($self->stash('user')->{id} ~~ @{$realty_tag->$tag_name}) {
                my $t_tags = Mojo::Collection->new(grep { $_ != $self->stash('user')->{id} } @{$realty_tag->$tag_name});
                $realty_tag->$tag_name($t_tags->compact->uniq);
            } else {
                my $t_tags = Mojo::Collection->new(@{$realty_tag->$tag_name});
                push @$t_tags, ($user_id);
                $realty_tag->$tag_name($t_tags->compact->uniq);
            }
        } else {
            my $t_tags = Mojo::Collection->new(grep { $_ != $self->stash('user')->{id} } @{$realty_tag->$tag_name});
            $realty_tag->$tag_name($t_tags->compact->uniq);
        }
    }

    $realty_tag->save(changes_only => 1);

    my $res = {
        status => 'success',
        id => $id,
        realty => $_serialize->($self, $realty),
    };

    return $self->render(json => $res);
}

sub set_color_tag_multiple {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};
    my $user_id = $self->stash('user')->{id};

    my $color_tag_id = $self->param('color_tag_id');
    my $ids = Mojo::Collection->new($self->param('id[]'));

    my %realtys;
    my @errors;

    $ids->each(sub {
        my ($id, $idx) = @_;
        my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
        unless ($realty) {
            push @errors, $id;
            return;
        }

        my $realty_tag = Rplus::Model::RealtyColorTag::Manager->get_objects(query => [realty_id => $id],)->[0];
        if (!$realty_tag) {
            $realty_tag = Rplus::Model::RealtyColorTag->new(realty_id => $id);
        }

        for (my $i = 0; $i <= 7; $i ++) {
            my $tag_name = 'tag' . $i;
            if ($i == $color_tag_id) {
                if ($self->stash('user')->{id} ~~ @{$realty_tag->$tag_name}) {
                    my $t_tags = Mojo::Collection->new(grep { $_ != $self->stash('user')->{id} } @{$realty_tag->$tag_name});
                    $realty_tag->$tag_name($t_tags->compact->uniq);
                } else {
                    my $t_tags = Mojo::Collection->new(@{$realty_tag->$tag_name});
                    push @$t_tags, ($user_id);
                    $realty_tag->$tag_name($t_tags->compact->uniq);
                }
            } else {
                my $t_tags = Mojo::Collection->new(grep { $_ != $self->stash('user')->{id} } @{$realty_tag->$tag_name});
                $realty_tag->$tag_name($t_tags->compact->uniq);
            }
        }

        $realty_tag->save(changes_only => 1);
        $realtys{$realty->id} = $_serialize->($self, $realty);
    });

    my $res = {
        status => 'success',
        list => {%realtys},
        errors => [@errors],
    };

    return $self->render(json => $res);
}

sub update {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $acc_id = $self->session('user')->{account_id};
    my $user_id = $self->stash('user')->{id};

    my $id = $self->param('id');
    my $create_event = 0;
    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;


    for ($self->param) {

        if ($_ eq 'agent_id') {
            my $agent_id = $self->param_n('agent_id');

            unless ($self->has_permission(realty => write => $realty->agent_id)) {
                return $self->render(json => {error => 'Forbidden'}, status => 403 , data => {uid => $user_id, aid => $agent_id,},) unless $self->has_permission(realty => 'write')->{can_assign} && $agent_id == $user_id;
            }
        } elsif ($_ eq 'color_tag_id') {
            # без проверок
        } elsif ($_ eq 'state_code' || $_ eq 'export_media' || $_ eq 'export_media[]') {
            return $self->render(json => {error => 'Forbidden'}, status => 403, data => $_) unless $self->has_permission(realty => write => $realty->agent_id);
        }
    }

    unless ($realty->account_id) {
        $realty = $_make_copy->($self, $realty);
        return $self->render(json => {error => 'Unable to make a copy'}, status => 404) unless $realty;
    }

    for ($self->param) {

        if ($_ eq 'agent_id') {
            my $agent_id = $self->param_n('agent_id');

            unless ($agent_id) {
                $realty->agent_id(undef);
            } else {
                if ($agent_id == 10000) {
                    add_mediator('ПОСРЕДНИК В НЕДВИЖИМОСТИ', $realty->owner_phones->[0], 'user_' . $user_id, $acc_id);
                } else {
                    $realty->agent_id($agent_id);
                    $create_event = 1;
                }
            }

            $realty->assign_date('now()');
            $realty->change_date('now()');


        } elsif ($_ eq 'state_code') {
            $realty->state_code(scalar $self->param('state_code'));
            $realty->change_date('now()');
        } elsif ($_ eq 'color_tag_id') {

        } elsif ($_ eq 'export_media[]') {
            my $export_media_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT M.id, M.name FROM media M WHERE M.type = 'export' AND M.delete_date IS NULL}, 'id');
            $realty->export_media(Mojo::Collection->new($self->param('export_media[]'))->grep(sub { exists $export_media_ok->{$_} })->uniq);

        } elsif ($_ eq 'export_media') {
            $realty->export_media(Mojo::Collection->new());
        }
    }

    if ($realty->state_code eq 'work' && !$realty->agent_id) {
        $realty->state_code('raw');
    }

    if (!$realty->agent_id) {
        $realty->export_media(Mojo::Collection->new());
    }

    if ($realty->state_code ne 'work') {
        $realty->multylisting(0);
    }

    # Save data
    eval {
        $realty->save(changes_only => 1);
        1;
    } or do {

        return $self->render(json => {error => $@}, status => 500) unless $realty;
    };

    $realty->load;

    eval {
        if ($create_event) {
            my $start_date = localtime;
            my $end_date = $start_date + 15 * 60;
            my $start_date_str = $start_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));
            my $end_date_str = $end_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));

            my @parts;
            {
                push @parts, $realty->type->name;
                push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                push @parts, $realty->price.' тыс. руб.' if $realty->price;
            }
            my $summary = join(', ', @parts);

            Rplus::Util::Task::qcreate($self, {
                    task_type_id => 9, # назначен объект
                    assigned_user_id => $realty->agent_id,
                    start_date => $start_date_str,
                    end_date => $end_date_str,
                    summary => $summary,
                    client_id => undef,
                    realty_id => $realty->id,
                });        
        }    
    };
    if ($@) {
        
    }
    
    my $res = {
        status => 'success',
        id => $realty->id,
        realty => $_serialize->($self, $realty),
    };

    return $self->render(json => $res);
}

sub update_multiple {
    my $self = shift;

    # Increase inactivity timeout for connection a bit
    Mojo::IOLoop->stream($self->tx->connection)->timeout(600);
    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $acc_id = $self->session('user')->{account_id};
    my $user_id = $self->stash('user')->{id};

    my $ids = Mojo::Collection->new($self->param('id[]'));

    my %realtys;
    my @errors;

    $ids->each(sub {
        my ($id, $idx) = @_;

        my $create_event = 0;
        my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
        unless ($realty) {
            push @errors, $id;
            return;
        }
        my $old_id = $realty->id;

        for ($self->param) {

            if ($_ eq 'agent_id') {
                my $agent_id = $self->param_n('agent_id');

                unless ($self->has_permission(realty => write => $realty->agent_id)) {
                    unless ($self->has_permission(realty => 'write')->{can_assign} && $agent_id == $user_id) {
                        push @errors, $id;
                        return;
                    }
                }
            } elsif ($_ eq 'color_tag_id') {
                
            } elsif ($_ eq 'export_media') {
                my $export_media_id = $self->param_n('export_media');
                my $export_media_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT M.id, M.name FROM media M WHERE M.type = 'export' AND M.delete_date IS NULL}, 'id');

                unless ($self->has_permission(realty => write => $realty->agent_id) || !exists $export_media_ok->{$export_media_id}) {
                    push @errors, $id;
                    return;
                }
            } elsif ($_ eq 'state_code') {
                unless ($self->has_permission(realty => write => $realty->agent_id)) {
                    push @errors, $id;
                    return;
                }
            } 
        }

        unless ($realty->account_id) {
            $realty = $_make_copy->($self, $realty);
            unless ($realty) {
                push @errors, $id;
                return;
            }
        }

        for ($self->param) {

            if ($_ eq 'agent_id') {
                my $agent_id = $self->param_n('agent_id');

                unless ($agent_id) {
                    $realty->agent_id(undef);
                } else {
                    if ($agent_id == 10000) {
                        add_mediator('ПОСРЕДНИК В НЕДВИЖИМОСТИ', $realty->owner_phones->[0], 'user_' . $user_id, $acc_id);
                    } else {
                        $realty->agent_id($agent_id);
                        $create_event = 1;
                    }
                }

                $realty->assign_date('now()');
                $realty->change_date('now()');


            } elsif ($_ eq 'state_code') {
                $realty->state_code(scalar $self->param('state_code'));
                $realty->change_date('now()');
            } elsif ($_ eq 'color_tag_id') {

            } elsif ($_ eq 'export_media') {
                my $export_media_id = $self->param_n('export_media');

                if ($export_media_id ~~ @{$realty->export_media}) {
                    my $new_export_media = Mojo::Collection->new(grep { $_ != $export_media_id } @{$realty->export_media});
                    $realty->export_media($new_export_media->compact->uniq);
                } else {
                    my $new_export_media = Mojo::Collection->new(@{$realty->export_media});
                    push @$new_export_media, ($export_media_id);
                    $realty->export_media($new_export_media->compact->uniq);
                }
            } elsif ($_ eq 'export_media') {
                $realty->export_media(Mojo::Collection->new());
            }
        }

        if ($realty->state_code eq 'work' && !$realty->agent_id) {
            $realty->state_code('raw');
        }

        if (!$realty->agent_id) {
            $realty->export_media(Mojo::Collection->new());
        }

        if ($realty->state_code ne 'work') {
            $realty->multylisting(0);
        }

        # Save data
        eval {
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

        eval {
            if ($create_event) {
                my $start_date = localtime;
                my $end_date = $start_date + 15 * 60;
                my $start_date_str = $start_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));
                my $end_date_str = $end_date->datetime . '+' . ($start_date->tzoffset / (60 * 60));

                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                }
                my $summary = join(', ', @parts);

                Rplus::Util::Task::qcreate($self, {
                        task_type_id => 9, # назначен объект
                        assigned_user_id => $realty->agent_id,
                        start_date => $start_date_str,
                        end_date => $end_date_str,
                        summary => $summary,
                        client_id => undef,
                        realty_id => $realty->id,
                    });        
            }    
        };
        if ($@) {
            
        }

    });

    my $res = {
        status => 'success',
        list => {%realtys},
        errors => [@errors],
    };

    return $self->render(json => $res);
}

sub check_coords {
    my $self = shift;

    my $id = $self->param('id');
    my $acc_id = $self->session('user')->{account_id};
    my $user_id = $self->stash('user')->{id};

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, or => [account_id => undef, account_id => $acc_id], \("NOT hidden_for && '{".$acc_id."}'"), delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    
    unless ($realty->latitude) {
        if ($realty->address_object && $realty->house_num) {
            my %coords = Rplus::Util::Geo::get_coords_by_addr($realty->address_object, $realty->house_num);
            if (%coords) {
                $realty->latitude($coords{latitude});
                $realty->longitude($coords{longitude});
                $realty->save(changes_only => 1);
            }
        }
    }
    
    if ($realty->latitude) {
        return $self->render(json => {status => 'success', lat => $realty->latitude, lng => $realty->longitude});
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
