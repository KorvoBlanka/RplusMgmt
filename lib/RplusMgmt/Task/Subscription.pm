package RplusMgmt::Task::Subscription;

use Rplus::Modern;

use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::SubscriptionRealty;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;

use Rplus::Util::Query;

use JSON;

sub run {
    my $class = shift;
    my $c = shift;

    # Выберем активные подписки
    my $subscr_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(query => [end_date => {gt => \'now()'}, delete_date => undef], require_objects => ['client'], sort_by => 'id');
    while (my $subscr = $subscr_iter->next) {
        $c->app->log->debug("Processing subscription #".$subscr->id);
        for my $q (@{$subscr->queries}) {
            $c->app->log->debug("Query: $q");
            # Исключим FTS данные
            my @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^t1\.fts/ ? () : $_ } (Rplus::Util::Query->parse($q));

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    offer_type_code => $subscr->offer_type_code,
                    state_code => 'work',
                    or => [
                        state_change_date => {gt => $subscr->add_date},
                        price_change_date => {gt => ($subscr->last_check_date || $subscr->add_date)},
                    ],
                    [\"t1.id NOT IN (SELECT SR.realty_id FROM subscription_realty SR WHERE SR.subscription_id = ? AND SR.delete_date IS NULL)" => $subscr->id],
                    delete_date => undef,
                    @query
                ],
                with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
            );
            my $found = 0;
            while (my $realty = $realty_iter->next) {
                $found++;
                Rplus::Model::SubscriptionRealty->new(subscription_id => $subscr->id, realty_id => $realty->id)->save;

                # Подготовим СМС для _клиента_
                if ($subscr->client->phone_num =~ /^9\d{9}$/) {
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
                    my $sms_text = 'По вашему запросу поступило: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').($c->config->{subscription}->{contact_info} ? ' '.$c->config->{subscription}->{contact_info} : '');
                    Rplus::Model::SmsMessage->new(phone_num => $subscr->client->phone_num, text => $sms_text)->save;
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
                        push @parts, 'Клиент: '.($subscr->client->phone_num =~ s/^(\d{3})(\d{3})(\d{4})/($1) $2 $3/r);
                    }
                    my $sms_text = 'Подобрано: '.join(', ', @parts);
                    Rplus::Model::SmsMessage->new(phone_num => $realty->agent->phone_num, text => $sms_text)->save;
                }

            }
            $c->app->log->debug("Found: $found");
        }
    }

    return;
}

1;
