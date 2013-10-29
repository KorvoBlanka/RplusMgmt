package RplusMgmt::Controller::API::Analytics::Subscription;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use DateTime::Format::Pg;
use Rplus::Util::Query;
use JSON;

sub auth {
    my $self = shift;

    #my $user_role = $self->session->{'user'}->{'role'};
    #if ($user_role && $self->config->{'roles'}->{$user_role}->{'configuration'}->{'analytics'}) {
        return 1;
    #}

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $date1 = $self->param('date1') // '';
    my $date2 = $self->param('date2') // '';
    my $offer_type_code = $self->param('offer_type');
    my $active = $self->param('active');

    my $res = {
        count => 0,
        list => [],
    };

    my ($dt1, $dt2);
    if ($date1 =~ /^\d{4}-\d{2}-\d{2}$/ && $date2 =~ /^\d{4}-\d{2}-\d{2}$/) {
        eval {
            $dt1 = DateTime::Format::Pg->parse_datetime("$date1 00:00:00"); $dt1->set_time_zone('local');
            $dt2 = DateTime::Format::Pg->parse_datetime("$date2 23:59:59"); $dt2->set_time_zone('local');
            1;
        } or do {};
    }
    return $self->render(json => $res) unless $dt1 && $dt2;

    # Load subscription data
    my $subscr_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(
        query => [
            offer_type_code => $offer_type_code,
            add_date => {between => [$dt1, $dt2]},
            ($active ? \'t1.end_date > now()' : ('!end_date' => undef)),
            delete_date => undef,
        ],
        require_objects => ['client'],
        with_objects => ['subscription_realty'],
        sort_by => 'id',
    );
    my %realty_h;
    while (my $subscr = $subscr_iter->next) {
        my $x = {
            id => $subscr->id,
            client => {
                id => $subscr->client->id,
                name => $subscr->client->name,
                phone_num => $subscr->client->phone_num,
            },
            queries => scalar $subscr->queries,
            add_date => $subscr->add_date,
            end_date => $subscr->end_date,
            realty => [],
        };
        push @{$res->{list}}, $x;

        for (@{$subscr->subscription_realty}) {
            $realty_h{$_->realty_id} = [] unless exists $realty_h{$_->realty_id};
            push @{$realty_h{$_->realty_id}}, $x;
        }
    }

    # Load realty data for subscriptions
    if (keys %realty_h) {
        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
            query => [id => [keys %realty_h]],
            with_objects => ['address_object', 'sublandmark'],
            sort_by => 'id',
        );
        while (my $realty = $realty_iter->next) {
            my $x = {
                id => $realty->id,
                type_code => $realty->type_code,
                offer_type_code => $realty->offer_type_code,
                house_num => $realty->house_num,
                rooms_count => $realty->rooms_count,
                rooms_offer_count => $realty->rooms_offer_count,
                price => $realty->price,
                agent_id => $realty->agent_id,

                address_object => $realty->address_object_id ? {
                    id => $realty->address_object->id,
                    name => $realty->address_object->name,
                    short_type => $realty->address_object->short_type,
                    expanded_name => $realty->address_object->expanded_name,
                    addr_parts => decode_json($realty->address_object->metadata)->{'addr_parts'},
                } : undef,
                sublandmark => $realty->sublandmark ? {id => $realty->sublandmark->id, name => $realty->sublandmark->name} : undef
            };
            push @{$_->{realty}}, $x for @{$realty_h{$realty->id}};
        }
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

1;
