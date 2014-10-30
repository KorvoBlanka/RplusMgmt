package RplusMgmt::Controller::API::Realty;

use Mojo::Base 'Mojolicious::Controller';

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
use Rplus::Model::ColorTag;
use Rplus::Model::ColorTag::Manager;

use Rplus::Util::PhoneNum;
use Rplus::Util::Query;
use Rplus::Util::Realty;
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::Task;

use JSON;
use Mojo::Collection;
use Time::Piece;

use Data::Dumper;

no warnings 'experimental::smartmatch';

# Private function: serialize realty object(s)
my $_serialize = sub {
    my $self = shift;
    my @realty_objs = (ref($_[0]) eq 'ARRAY' ? @{shift()} : shift);
    my %params = @_;

    my @exclude_fields = qw(ap_num source_media_id source_media_text owner_phones work_info);
    my @exclude_fields_agent_plus = qw(ap_num source_media_text work_info);

    my (@serialized, %realty_h);
    for my $realty (@realty_objs) {
        
        my $meta = from_json($realty->metadata);
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
            mediator_company => ($realty->mediator_company && $realty->agent_id == 10000) ? $realty->mediator_company->name : '',
            reference => '',
        };
        
        my $vals = from_json($realty->metadata);
        $x->{reference} = $vals->{'reference'};

        if ($realty->color_tags) {
            foreach($realty->color_tags) {
                if ($_->{user_id} == $self->stash('user')->{id}) {
                    $x->{color_tag_id} = $_->{color_tag_id};
                    last;
                }
            }
        }

        # Exclude fields for read permission "2"
        if ($realty->agent_id && $realty->agent_id != 10000 && $self->has_permission(realty => read => $realty->agent_id) == 2) {
            $x->{$_} = undef for @exclude_fields;
            
            my $user = Rplus::Model::User::Manager->get_objects(query => [id => $realty->agent_id, delete_date => undef])->[0];
            $x->{owner_phones} = [$user->public_phone_num];
        }

        # Exclude fields for read permission "3"
        if ($realty->agent_id && $realty->agent_id != 10000 && $self->has_permission(realty => read => $realty->agent_id) == 3) {
            $x->{$_} = undef for @exclude_fields_agent_plus;
            
            my $user = Rplus::Model::User::Manager->get_objects(query => [id => $realty->agent_id, delete_date => undef])->[0];
            $x->{owner_phones} = [$user->public_phone_num];            
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
    $self->validation->optional('agent_id')->like(qr/^(?:\d+|any|all|not_med|nobody)$/);
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
    my $agent_id = $self->param('agent_id') || 'any';
    my $sort_by = $self->param('sort_by');
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 30;
    my $color_tag_id = $self->param("color_tag_id") || 'any';

    # "where" query
    my @query;
    {
        if ($color_tag_id ne 'any') {
            push @query, and => [
                'color_tags.color_tag_id' => $color_tag_id,
                'color_tags.user_id' => $self->stash('user')->{id}];
        }
          
        if ($state_code ne 'any') { push @query, state_code => $state_code } else { push @query, '!state_code' => 'deleted' };
        if ($offer_type_code ne 'any') { push @query, offer_type_code => $offer_type_code };
        if ($self->has_permission(realty => 'read')->{only_work}) {
          push @query, or => [
              agent_id => $self->stash('user')->{id},
              state_code => 'work',
          ];
        }

        my $agent_ok;
        if ($agent_id eq 'all' && $self->has_permission(realty => 'read')->{others}) {
            push @query, and => ['!agent_id' => undef, '!agent_id' => 10000];
            $agent_ok = 1;
        } elsif ($agent_id eq 'not_med') {
            push @query, 'agent_id' => undef;
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

    my $res = {
        count => Rplus::Model::Realty::Manager->get_objects_count(query => [@query, delete_date => undef], with_objects => ['color_tags', @with_objects]),
        list => [],
        page => $page,
    };

    # Delete FTS data if no objects found
    if (!$res->{count}) {
        @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } @query;
        $res->{count} = Rplus::Model::Realty::Manager->get_objects_count(query => [@query, delete_date => undef], with_objects => ['color_tags', @with_objects]);
    }

    # Additionaly check found phones for mediators
    if (@owner_phones) {
        my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(query => [phone_num => \@owner_phones, delete_date => undef], require_objects => ['company']);
        while (my $mediator = $mediator_iter->next) {
            push @{$res->{'mediators'}}, {id => $mediator->id, company => $mediator->company->name, phone_num => $mediator->phone_num};
        }
    }
    
    # Fetch realty objects
    my $realty_objs = Rplus::Model::Realty::Manager->get_objects(
        select => ['realty.*', (map { 'address_object.'.$_ } qw(id name short_type expanded_name metadata))],
        query => [@query, delete_date => undef],
        sort_by => [@sort_by, 'realty.last_seen_date desc'],
        page => $page,
        per_page => $per_page,
        with_objects => ['address_object', 'sublandmark', 'color_tags', 'mediator_company', @with_objects],
    );
    
    $res->{list} = [$_serialize->($self, $realty_objs)];

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'read');
    my $id = $self->param('id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, delete_date => undef], with_objects => ['address_object'])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => read => $realty->agent_id);
    
    my $res = $_serialize->($self, $realty, with_sublandmarks => 1);

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');
    
    my $create_event = 0;

    my $realty;
    if (my $id = $self->param('id')) {
        $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $realty = Rplus::Model::Realty->new(
            creator_id => $self->stash('user')->{id},
            agent_id => scalar $self->param('agent_id'),
        );
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id) || $self->has_permission(realty => 'write')->{can_assign} && $realty->agent_id == undef;

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
        'latitude', 'longitude', 'sublandmark_id',
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

    # Owner phones
    $data{owner_phones} = Mojo::Collection->new($self->param('owner_phones[]'))->map(sub { $self->parse_phone_num($_) })->compact->uniq;
    push @errors, {owner_phones => 'Empty phones'} unless @{$data{owner_phones}};

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
    my $tags_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT T.id, T.name FROM tags T WHERE T.delete_date IS NULL}, 'id');
    $data{tags} = Mojo::Collection->new($self->param('tags[]'))->grep(sub { exists $tags_ok->{$_} })->uniq;
    
    # Export media
    my $export_media_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT M.id, M.name FROM media M WHERE M.type = 'export' AND M.delete_date IS NULL}, 'id');
    $data{export_media} = Mojo::Collection->new($self->param('export_media[]'))->grep(sub { exists $export_media_ok->{$_} })->uniq;

    # Check for errors & check that we can rewrite agent
    return $self->render(json => {errors => \@errors}, status => 400) if @errors;
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $data{agent_id});

    # Find similar realty
    #my $similar_realty_id = Rplus::Util::Realty->find_similar(%data, state_code => ['raw', 'work', 'suspended']);
    #my $similar_realty = Rplus::Model::Realty->new(id => $similar_realty_id)->load(with => ['address_object']) if $similar_realty_id;

    if ($data{agent_id} && $data{agent_id} != 10000) {
        if ($realty->id) {
            if ($realty->agent_id != $data{agent_id}) {
                $create_event = 1;
            }
        } else {
            $create_event = 1;
        }
    }

    # if agent_id changed - set 'assign_date'
    $realty->assign_date('now()') if $realty->agent_id != $data{agent_id};

    # Save data
    $realty->$_($data{$_}) for keys %data;
    if ($changed) {
        $realty->change_date('now()');
    }

    # check owner phones for mediators
    my @owner_phones = $realty->owner_phones;
    if(scalar @owner_phones > 0) {
        if (Rplus::Model::Mediator::Manager->get_objects_count(query => [phone_num => \@owner_phones, delete_date => undef]) > 0) {
            $realty->agent_id(10000);
            if ($realty->state_code eq 'work') {
                $realty->state_code('raw');
            }
            my $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [phone_num => \@owner_phones, delete_date => undef], require_objects => ['company'])->[0];
            $realty->mediator_company_id($mediator->company->id);

            # добавить все телефоны в посредники
            for (@owner_phones) {
                add_mediator($mediator->company->name, $_, 'user_' . $self->stash('user')->{id});
            }
        } else {
            if ($realty->agent_id == 10000) {
                $realty->agent_id(undef);
                $realty->mediator_company_id(undef);
            }
        }
    }

    eval {
        $realty->save($realty->id ? (changes_only => 1) : (insert => 1));
        1;
    } or do {
        return $self->render(json => {error => $@}, status => 500) unless $realty;
    };

    my $user_id = $self->stash('user')->{id};
    my $color_tag = Rplus::Model::ColorTag::Manager->get_objects(query => [realty_id => $realty->id, user_id => $user_id,])->[0];
    if ($color_tag) {
        if ($color_tag_id != $color_tag->color_tag_id) {
          $color_tag->color_tag_id($color_tag_id);
        } else {
          #$color_tag->color_tag_id(undef);
        }
        $color_tag->save(changes_only => 1);
    } else {
        $color_tag = Rplus::Model::ColorTag->new(
            realty_id => $realty->id,
            user_id => $user_id,
            color_tag_id => $color_tag_id,
        );
        $color_tag->save(insert => 1);
    }    
    
    $realty->load;

    my $res = {
        status => 'success',
        id => $realty->id,
        realty => $_serialize->($self, $realty),
        #similar_realty_id => $similar_realty_id,
        #($similar_realty ? (similar_realty => $_serialize->($self, $similar_realty)) : ()),
    };

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

    $self->render(json => $res);
}

sub update {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'write');

    my $id = $self->param('id');
    my $create_event = 0;
    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $realty;

    my $user_id = $self->stash('user')->{id};
    # Available fields to set: agent_id, state_code
    for ($self->param) {
        if ($_ eq 'agent_id') {
            return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id) || ($self->has_permission(realty => 'write')->{can_assign} && $realty->agent_id == undef);
            # if agent_id changed - set 'assign_date'
            $realty->assign_date('now()');
            if ($self->param('agent_id') && $self->param('agent_id') != 10000 && $self->param('agent_id') != $realty->agent_id) {
                $create_event = 1
            }
            unless ($self->param('agent_id')) {
                $realty->agent_id(undef);
            } else {
                my $agent_id = $self->param_n('agent_id');
                $realty->agent_id(scalar $self->param('agent_id'));
                if ($agent_id == 10000) {
                    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);
                    my $company = 'ПОСРЕДНИК В НЕДВИЖИМОСТИ';
                    add_mediator($company, $realty->owner_phones->[0], 'user_' . $self->stash('user')->{id});
                }
            }
            return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);
            $realty->change_date('now()');
        } elsif ($_ eq 'state_code') {
            return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);
            return $self->render(json => {error => 'Forbidden'}, status => 403) if $realty->agent_id == 10000 && $self->param('state_code') eq 'work';
            $realty->state_code(scalar $self->param('state_code'));
            $realty->change_date('now()');
        } elsif ($_ eq 'color_tag_id') {
            my $color_tag_id = $self->param('color_tag_id');
            my $color_tag = Rplus::Model::ColorTag::Manager->get_objects(query => [realty_id => $realty->id, user_id => $user_id,])->[0];
            if ($color_tag) {
                if ($color_tag_id != $color_tag->color_tag_id) {
                  $color_tag->color_tag_id($color_tag_id);
                } else {
                  $color_tag->color_tag_id(undef);
                }
                $color_tag->save(changes_only => 1);
            } else {
                $color_tag = Rplus::Model::ColorTag->new(
                    realty_id => $realty->id,
                    user_id => $user_id,
                    color_tag_id => $color_tag_id,
                );
                $color_tag->save(insert => 1);
            }
        } elsif ($_ eq 'export_media[]') {
            return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);
            my $export_media_ok = Rplus::DB->new_or_cached->dbh->selectall_hashref(q{SELECT M.id, M.name FROM media M WHERE M.type = 'export' AND M.delete_date IS NULL}, 'id');
            $realty->export_media(Mojo::Collection->new($self->param('export_media[]'))->grep(sub { exists $export_media_ok->{$_} })->uniq);
        } elsif ($_ eq 'export_media') {
            return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => write => $realty->agent_id);
            $realty->export_media(Mojo::Collection->new());
        }
    }

    if ($realty->state_code eq 'work' && !$realty->agent_id) {
        return $self->render(json => {error => 'Forbidden'}, status => 403);
    }

    # Save data
    eval {
        $realty->save(changes_only => 1);
        1;
    } or do {
        return $self->render(json => {error => $@}, status => 500) unless $realty;
    };

    $realty->load;

    my $res = {
        status => 'success',
        id => $realty->id,
        realty => $_serialize->($self, $realty),
    };

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
    
    return $self->render(json => $res);
}

1;
