package RplusMgmt::Controller::API::Subscription;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Rplus::DB;

use JSON;
use Rplus::Util::PhoneNum;

sub auth {
    my $self = shift;

    #my $user_role = $self->session->{'user'}->{'role'};
    #if ($user_role && $self->config->{'roles'}->{$user_role}->{'configuration'}->{'landmarks'}) {
    #    return 1;
    #}
    return 1;

    $self->render_not_found;
    return undef;
}

sub add {
    my $self = shift;

    my $q = $self->param('q');
    my $offer_type_code = $self->param('offer_type');
    my @realty_ids = $self->param('realty_id[]');
    my $active = $self->param('active');
    my $phone_num = Rplus::Util::PhoneNum->parse(scalar $self->param('phone_num'));

    return $self->render(json => {status => 'failed'}) unless $q && $offer_type_code && $phone_num;

    my $db = Rplus::DB->new_or_cached;
    $db->begin_work;

    # Найдем/добавим клиента по номеру телефона
    my $client = Rplus::Model::Client::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef], db => $db)->[0];
    if (!$client) {
        $client = Rplus::Model::Client->new(name => $phone_num, login => $phone_num, phone_num => $phone_num, db => $db);
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
                my $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').' Офис: тел. 470-470';
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
