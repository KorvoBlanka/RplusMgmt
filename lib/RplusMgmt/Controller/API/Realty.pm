package RplusMgmt::Controller::API::Realty;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;

use Rplus::DB;

use Rplus::Util::Query;
use Rplus::Util::Realty;
use Rplus::Util::PhoneNum;

use JSON;

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

    my $q = $self->param('q');
    my $state_code = $self->param('state');
    my $offer_type_code = $self->param('offer_type');
    my $agent_id = $self->param('agent');
    my $sort_by = $self->param('sort');
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 30;

    my @query;
    if ($state_code && $state_code ne 'any') { push @query, state_code => $state_code } else { push @query, '!state_code' => 'deleted' };   
    if ($offer_type_code && $offer_type_code ne 'any') { push @query, offer_type_code => $offer_type_code } else {};
    if ($agent_id && $agent_id ne 'any') {
        if ($agent_id eq 'nobody') {
            push @query, agent_id => undef
        } elsif ($agent_id eq 'all') {
            push @query, '!agent_id' => undef
        } else {
            push @query, agent_id => $agent_id
        }
    }

    my (@sort_by, @with_objects);
    if  ($sort_by && $sort_by =~ /^(\w+)(\.\w+)? (asc|desc)$/) {
      push @with_objects, $1 if $1 && $2;
      push @sort_by, $sort_by;
    }

    # Распознаем номера телефонов
    my @seller_phones;
    {
        for my $x (split /[ .,]/, $q) {
            if ($x =~ /^\s*([\d-]{6,})\s*$/) {
                if (my $phone_num = Rplus::Util::PhoneNum->parse($1)) {
                    push @seller_phones, $phone_num;
                }
                $q =~ s/$x//;
            }
        }
        push @query, \("t1.seller_phones && '{".join(',', map { '"'.$_.'"' } @seller_phones)."}'") if @seller_phones;
    }

    # Остальные части запроса
    push @query, Rplus::Util::Query->parse($q, $self);

    my $res = {
        count => Rplus::Model::Realty::Manager->get_objects_count(query => \@query, with_objects => \@with_objects),
        list => [],
        page => $page,
    };

    # Небольшой костыль: если ничего не найдено, удалим FTS данные
    if (!$res->{count}) {
        @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } @query;
        $res->{count} = Rplus::Model::Realty::Manager->get_objects_count(query => \@query, with_objects => \@with_objects);
    }

    # Дополнительно проверим распознанные номера телефонов на посредников
    if (@seller_phones) {
        my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(query => [phone_num => \@seller_phones, delete_date => undef], require_objects => ['company']);
        while (my $mediator = $mediator_iter->next) {
            push @{$res->{'mediators'}}, {id => $mediator->id, company => $mediator->company->name, phone_num => $mediator->phone_num};
        }
    }

    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
        select => ['realty.*', map { 'address_object.'.$_ } ('id', 'name', 'short_type', 'expanded_name', 'metadata')],
        query => \@query,
        sort_by => [@sort_by, 'realty.id desc'],
        page => $page,
        per_page => $per_page,
        with_objects => ['address_object', 'sublandmark', @with_objects],
    );
    while (my $realty = $realty_iter->next) {
        my $metadata = decode_json($realty->metadata);
        push @{$res->{'list'}}, {
            address_object => $realty->address_object_id ? {
                id => $realty->address_object->id,
                name => $realty->address_object->name,
                short_type => $realty->address_object->short_type,
                expanded_name => $realty->address_object->expanded_name,
                addr_parts => decode_json($realty->address_object->metadata)->{'addr_parts'},
            } : undef,

            sublandmark => $realty->sublandmark ? {id => $realty->sublandmark->id, name => $realty->sublandmark->name} : undef,

            (map { $_ => scalar $realty->$_ } grep { !/^(?:metadata)|(?:geocoords)|(?:fts)|(?:landmarks)$/ } $realty->meta->column_names)
        };
    }

    $self->render(json => $res);
}

sub get {
    my $self = shift;

    my $id = $self->param('id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(query => [id => $id], with_objects => ['address_object'])->[0];
    return $self->render_not_found unless $realty;

    # TODO: Access Control

    my $metadata = decode_json($realty->metadata);
    my $res = {
        address_object => $realty->address_object_id ? {
            id => $realty->address_object->id,
            name => $realty->address_object->name,
            short_type => $realty->address_object->short_type,
            expanded_name => $realty->address_object->expanded_name,
            addr_parts => decode_json($realty->address_object->metadata)->{'addr_parts'},
        } : undef,

        sublandmarks => @{$realty->landmarks} ? [
            map { {id => $_->id, name => $_->name} } @{Rplus::Model::Landmark::Manager->get_objects(
                select => 'id, name',
                query => [id => [@{$realty->landmarks}, $realty->sublandmark_id || ()], type => 'sublandmark', delete_date => undef],
                sort_by => 'name'
            )}
        ] : [],

        (map { $_ => scalar $realty->$_ } grep { !/^(?:metadata)|(?:geocoords)|(?:fts)|(?:landmarks)$/ } $realty->meta->column_names)
    };

    return $self->render(json => $res);
}

sub create {
    my $self = shift;

    my $x = Rplus::DB->new_or_cached->dbh->selectrow_arrayref("SELECT nextval('realty_id_seq')");

    $self->render(json => {id => $x->[0]});
}

sub save {
    my $self = shift;

    my $id = $self->param('id');
    my %data;
    for my $p ($self->param) {
        if ($p =~ /\[\]$/) {
            $data{$p =~ s/\[\]$//r} = [$self->param($p)];
        } else {
            $data{$p} = $self->param($p) || undef;
            if ($p =~ /ˆsquare_/ || $p=~ /_price$/) {
                $data{$p} =~ s/,/./ if $data{$p};
            }
        }
    }

    return $self->render(json => {status => 'failed', error_msg => 'No id specified'}) unless $id;

    # Поиск похожих вариантов
    my $similar_realty_id = Rplus::Util::Realty->find_similar(%data, state_code => ['raw', 'work', 'suspended']);
    my $similar_realty = Rplus::Model::Realty->new(id => $similar_realty_id)->load(with => ['address_object']) if $similar_realty_id;

    my $realty = Rplus::Model::Realty->new(id => $id)->load(speculative => 1);
    # TODO: Access control
    $realty = Rplus::Model::Realty->new(id => $id) unless $realty;

    for my $f (@{$realty->meta->column_names}) {
        next if $f eq 'id';
        next if $f =~ /_date$/;
        next if $f eq 'creator_id';
        next if $f eq 'price';
        next if $f eq 'geocoords';
        next if $f eq 'landmarks';
        next if $f eq 'fts';
        next if $f eq 'metadata';

        if (exists $data{$f}) {
            if ($f eq 'export_media') {
                my @export_media;
                if (ref($data{$f}) eq 'ARRAY' && @{$data{$f}}) {
                    my $x = Rplus::DB->new_or_cached()->dbh->selectall_hashref(q{SELECT J.* FROM media M, json_each_text(M.metadata->'export_codes') J WHERE M.type='export' AND M.delete_date IS NULL}, 'key');
                    @export_media = grep { exists $x->{$_} } @{$data{$f}};
                }
                $realty->export_media(\@export_media);
            } elsif ($f eq 'tags') {
            } elsif ($f eq 'seller_phones') {
                my @seller_phones;
                if (ref($data{$f}) eq 'ARRAY') {
                    @seller_phones = map { Rplus::Util::PhoneNum->parse($_) } @{$data{$f}};
                }
                $realty->seller_phones(\@seller_phones);
            } else {
                $realty->$f($data{$f});
            }
        }
    }

    $realty->save($realty->id ? (changes_only => 1) : (insert => 1));
    Rplus::Model::Realty::Manager->update_objects(set => {change_date => \"now()"}, where => [id => $realty->id]);
    $realty->load;

    my $metadata = decode_json($realty->metadata);
    my $res = {
        address_object => $realty->address_object_id ? {
            id => $realty->address_object->id,
            name => $realty->address_object->name,
            short_type => $realty->address_object->short_type,
            expanded_name => $realty->address_object->expanded_name,
            addr_parts => decode_json($realty->address_object->metadata)->{'addr_parts'},
        } : undef,

        sublandmarks => @{$realty->landmarks} ? [
            map { {id => $_->id, name => $_->name} } @{Rplus::Model::Landmark::Manager->get_objects(
                select => 'id, name',
                query => [id => [@{$realty->landmarks}, $realty->sublandmark_id || ()], type => 'sublandmark', delete_date => undef],
                sort_by => 'name'
            )}
        ] : [],

        (map { $_ => scalar $realty->$_ } grep { !/^(?:metadata)|(?:geocoords)|(?:fts)$/ } $realty->meta->column_names),

        ($similar_realty ? (similar => {
            id => $similar_realty->id,
            type_code => $similar_realty->type_code,
            address_object => $similar_realty->address_object_id ? {
                id => $similar_realty->address_object->id,
                name => $similar_realty->address_object->name,
                short_type => $similar_realty->address_object->short_type,
                expanded_name => $similar_realty->address_object->expanded_name,
            } : undef,
            house_num => $similar_realty->house_num,
        }) : ())
    };

    $self->render(json => {status => 'success', data => $res});
}

sub interest {
    my $self = shift;

    my $q = $self->param('q');
    my $offer_type_code = $self->param('offer_type_code');
    my @realty_ids = $self->param('realty_id[]');
    my $active = $self->param('active');
    my $phone_num = Rplus::Util::PhoneNum->parse(scalar $self->param('phone_num'));

    return $self->render(json => {status => 'failed'}) unless $q && $offer_type_code && $phone_num;

    my $db = Rplus::DB->new_or_cached;
    $db->begin_work;

    # Найдем/добавим клиента по номеру телефона
    my $client = Rplus::Model::Client::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef], db => $db)->[0];
    if (!$client) {
        $client = Rplus::Model::Client->new(phone_num => $phone_num, db => $db);
        $client->save;
    }

    # Добавим подписку
    my $subscription = Rplus::Model::Subscription->new(
        client_id => $client->id,
        user_id => $self->session->{'user'}->{'id'},
        queries => [$q],
        offer_type_code => $offer_type_code,
        db => $db,
    );
    $subscription->save;

    # Активирум при необходимости
    if ($active) {
        Rplus::Model::Subscription::Manager->update_objects(
            set => {end_date => \"add_date + interval '2 weeks'"},
            where => [id => $subscription->id],
            db => $db,
        );
    }

    # Добавим недвижимость
    for my $realty_id (@realty_ids) {
        next unless $realty_id;

        my $realty = Rplus::Model::Realty::Manager->get_objects(
            query => [id => $realty_id, state_code => ['raw', 'work'], offer_type_code => $offer_type_code],
            with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
            db => $db,
        )->[0];
        if ($realty) {
            Rplus::Model::SubscriptionRealty->new(subscription_id => $subscription->id, realty_id => $realty->id, db => $db)->save;

            # Подготовим СМС для _клиента_
            if ($phone_num =~ /^9\d{9}$/) {
                # TODO: Добавить настройки шаблонов
                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->address_object->name !~ /[()]/ && $realty->sublandmark ? ' ('.$realty->sublandmark->name.')' : '') if $realty->address_object;
                    push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                    push @parts, decode_json($realty->agent->metadata)->{'public_name'} || $realty->agent->name if $realty->agent;
                    push @parts, decode_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num if $realty->agent;
                }
                my $sms_body = join(', ', @parts);
                my $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').($self->config->{subscription}->{contact_info} ? ' '.$self->config->{subscription}->{contact_info} : '');
                Rplus::Model::SmsMessage->new(phone_num => $phone_num, text => $sms_text, db => $db)->save;
            }

            # Подготовим СМС для _агента_
            if ($realty->agent && ($realty->agent->phone_num || '') =~ /^9\d{9}$/) {
                # TODO: Добавить настройки шаблонов
                my @parts;
                {
                    push @parts, $realty->type->name;
                    push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
                    push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->house_num ? ', '.$realty->house_num : '') if $realty->address_object;
                    push @parts, $realty->price.' тыс. руб.' if $realty->price;
                    push @parts, 'Клиент: '.($phone_num =~ s/^(\d{3})(\d{3})(\d{4})/($1) $2 $3/r);
                }
                my $sms_text = join(', ', @parts);
                Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text, db => $db)->save;
            }
        }
    }

    $db->commit;

    return $self->render(json => {status => 'success'});
}

1;
