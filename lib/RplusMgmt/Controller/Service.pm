package RplusMgmt::Controller::Service;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::IOLoop;

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Model::User;
use Rplus::Model::User::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use JSON;


sub delete_account {
    my $self = shift;

    my $email = $self->param('email');

    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [email => $email, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    $account->del_date('now');
    $account->save;

    return $self->render(json => {status => 'success'})
}

sub create_account {
    my $self = shift;

    my $email = $self->param('email');
    my $name = $self->param('name');
    my $location_id = $self->param('location_id');

    my $options_str = '{';
    $options_str .= '"notifications":{"contact_info":"","company":"","login":"","msg-count":"14","email-smtp":"","email-user":"","password":"","email-password":"","active":false,"email-port":""},';
    $options_str .= '"multylisting":{"company-name":""},';
    $options_str .= '"export":{"farpost-agent-phone":false,"avito-phone":"","irr-email":"","vnh-agent-phone":false,"present-phones":"","vnh-phones":"","vnh-company":"","irr-agent-phone":false,"avito-email":"","irr-url":"","avito-company":"","present-descr":"5","irr-phones":"","farpost-phones":"","present-agent-phone":false,"avito-agent-phone":false},';
    $options_str .= '"import":{"rent-office":"true","rent-apartment_new":"true","sale-townhouse":"true","sale-apartment_new":true,"sale-land":"true","sale-room":true,"sale-house":"true","rent-room":"true","rent-other":"true","sale-cottage":"true","rent-apartment":"true","rent-cottage":"true","rent-dacha":"true","sale-office":"true","rent-house":"true","sale-apartment":true,"rent-apartment_small":"true","rent-townhouse":"true","sale-apartment_small":true,"sale-other":"true","sale-dacha":"true","rent-land":"true"}';
    $options_str .= '}';


    my $telephony_str = '{"sip_login":"user","sip_password":"000","sip_host":"host"}';

    my $account;

    # Begin transaction
    my $db = $self->db;
    $db->begin_work;

    eval {
        $account = Rplus::Model::Account->new (
            email => $email,
            name => $name,
            location_id => $location_id,
            company_name => $name,
        );
        $account->save;


        my $options = Rplus::Model::Option->new (
            options => $options_str,
            account_id => $account->id,
        );
        $options->save;

        my $user = Rplus::Model::User->new (
            login => 'manager',
            password => '12345',
            role => 'top',
            name => 'manager',

            ip_telephony => $telephony_str,
            subordinate => Mojo::Collection->new,
            account_id => $account->id,
        );

        $user->save;
    } or do {
        $db->rollback;
        return $self->render(json => {status => 'fail'});
    };

    $db->commit;
    return $self->render(json => {status => 'success', account_id => $account->id});
}

sub list_users {
    my $self = shift;

    my $account_name = $self->param('account_name');

    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [name => $account_name, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    my $res = {
        count => 0,
        list => [],
    };

    my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(query => [account_id => $account->id, delete_date => undef], sort_by => 'role DESC');
    while (my $user = $user_iter->next) {
        if ($user->id != 10000) {
            my $x = {
                id => $user->id,
                login => $user->login,
                password => $user->password,
                role => $user->role,
                name => $user->name,
                phone_num => $user->phone_num,
                description => $user->description,
                add_date => $self->format_datetime($user->add_date),
                photo_url => $user->photo_url ? $user->photo_url : '',
                offer_mode => $user->offer_mode,
            };
            push @{$res->{list}}, $x;
        }
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => {status => 'success', data => $res});
}

sub reset_usr_pwd {
    my $self = shift;

    my $id = $self->param('id');
    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {status => 'fail'}) unless $user;

    $user->password('12345');
    $user->save;

    return $self->render(json => {status => 'success'});
}

1;
