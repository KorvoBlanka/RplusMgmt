package RplusMgmt::Controller::API::Notification;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Util::SMS qw(prepare_sms_text enqueue send_sms);
use Rplus::Util::Email qw(prepare_email_message send_email);
use Rplus::Util::History qw(notification_record);

use Mojo::Base 'Mojolicious::Controller';

use Encode qw(decode encode);
use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;

no warnings 'experimental::smartmatch';

sub by_sms {
    my $self = shift;
    my $client_id = $self->param('client_id');
    my $realty_id = $self->param('realty_id');
    my $sms_text = '';
    my $status = 'not sent';

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $client = Rplus::Model::Client::Manager->get_objects(query => [id => $client_id, delete_date => undef])->[0];
    my $realty = Rplus::Model::Realty::Manager->get_objects(
        query => [id => $realty_id,],
        with_objects => ['agent', 'type'],
    )->[0];

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    my $config;
    if ($options) {
        $config = from_json($options->{options})->{notifications};
    } else {
        return $self->render(json => {status => 'no config',});
    }

    # Prepare SMS for client
    if ($client->phone_num =~ /^9\d{9}$/) {
        my $sms_text = prepare_sms_text($realty, 'CLIENT', $client, $acc_id);
        my $sms = send_sms($client->phone_num, $sms_text, $acc_id);
        if ($sms) {
            notification_record($acc_id, $user_id, 'sms_send', $sms, 'OK');
            $status = 'success';
        } else {
            notification_record($acc_id, $user_id, 'sms_send', $sms, 'FAIL');
            $status = 'fail';
        }

        my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(query => [client_id => $client->id, delete_date => undef,]);
        while (my $subscription = $subscription_iter->next) {
            my $num_rows_updated = Rplus::Model::SubscriptionRealty::Manager->update_objects(
                set => {offered => 1},
                where => [realty_id => $realty->id, subscription_id => $subscription->id],
            );
        }
    }

    return $self->render(json => {status => $status, data => $config->{active},});
}

sub by_email {
    my $self = shift;
    my $client_id = $self->param('client_id');
    my $realty_id = $self->param('realty_id');
    my $email_text = '';
    my $status = 'not sent';

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    my $client = Rplus::Model::Client::Manager->get_objects(query => [id => $client_id, delete_date => undef])->[0];

    my $realty = Rplus::Model::Realty::Manager->get_objects(
        query => [id => $realty_id,],
        with_objects => ['agent', 'type'],
    )->[0];

    # Prepare email for client
    if ($client->email) {
        # TODO: Add template settings
        my $sender = Rplus::Model::User::Manager->get_objects(query => [id => $self->stash('user')->{id}, delete_date => undef])->[0];
        my $message = prepare_email_message($realty, $sender, $acc_id);

        if (send_email($client->email, 'Подобрана недвижимость', $message, $acc_id)) {
            notification_record($acc_id, $user_id, 'email_send', undef, 'OK');
            $status = 'success';
        } else {
            notification_record($acc_id, $user_id, 'email_send', undef, 'FAIL');
            $status = 'false';
        }
    }

    return $self->render(json => {status => $status,});
}

1;
