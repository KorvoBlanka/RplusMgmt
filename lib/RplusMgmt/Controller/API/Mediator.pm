package RplusMgmt::Controller::API::Mediator;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Rplus::DB;

use Mojo::Util qw(trim);
use Mojo::Collection;
use Rplus::Util::PhoneNum;

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'configuration'}->{'mediators'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $company_id = $self->param('company_id');

    my $company = Rplus::Model::MediatorCompany::Manager->get_objects(query => [id => $company_id, delete_date => undef])->[0];
    return $self->render_not_found unless $company;

    my $res = {
        count => 0,
        list => [],
    };
    my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(query => [company_id => $company->id, delete_date => undef], sort_by => 'phone_num');
    while (my $mediator = $mediator_iter->next) {
        push @{$res->{'list'}}, {
            id => $mediator->id,
            name => $mediator->name,
            phone_num => $mediator->phone_num,
        };
        $res->{'count'}++;
    }

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    my $id = $self->param('id');
    my $company_name = trim scalar($self->param('company_name'));
    my $name = trim scalar($self->param('name'));
    my $phone_num = Rplus::Util::PhoneNum->parse(scalar($self->param('phone_num')));

    my @errors;
    {
        push @errors, {field => 'company_name', msg => 'Empty company name'} unless $company_name;
        #push @errors, {field => 'name', msg => 'Empty mediatior name'} unless $name;
        push @errors, {field => 'phone_num', 'Invalid phone num'} unless $phone_num;
    }
    return $self->render(json => {status => 'failed', errors => \@errors}) if @errors;

    my $db = Rplus::DB->new_or_cached;
    $db->begin_work;

    my $mediator;
    if ($id) {
        $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [id => $id, delete_date => undef], db => $db)->[0];
        unless ($mediator) {
            $db->rollback;
            return $self->render_not_found;
        }
    } else {
        $mediator = Rplus::Model::Mediator->new(db => $db);
    }

    $mediator->name($name);
    $mediator->phone_num($phone_num);

    my ($num_realty_deleted, $update_company_list);
    eval {
        my $company = $mediator->company;
        unless ($company && lc($company->name) eq lc($company_name)) {
            $company = Rplus::Model::MediatorCompany::Manager->get_objects(query => [[\'lower(name) = ?' => lc($company_name)], delete_date => undef], db => $db)->[0];
            unless ($company) {
                $company = Rplus::Model::MediatorCompany->new(name => $company_name, db => $db);
                $company->save;
                $update_company_list = 1;
            }
            $mediator->company($company);
        }

        $mediator->save;

        # Search for additional mediator phones
        my $search_phones = Mojo::Collection->new();
        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(select => 'id, seller_phones', query => ['!state_code' => 'deleted', \("seller_phones && '{".$phone_num."}'")], db => $db);
        while (my $realty = $realty_iter->next) {
            push @$search_phones, ($realty->seller_phones);
        }
        $search_phones = $search_phones->uniq;

        if ($search_phones->size) {
            # Add additional mediators
            for (@$search_phones) {
                if ($_ ne $phone_num && !Rplus::Model::Mediator::Manager->get_objects_count(query => [phone_num => $_, delete_date => undef], db => $db)) {
                    Rplus::Model::Mediator->new(db => $db, name => $name, phone_num => $_, company => $company)->save;
                }
            }

            $num_realty_deleted = Rplus::Model::Realty::Manager->update_objects(
                set => {state_code => 'deleted', change_date => \'now()'},
                where => [
                    '!state_code' => 'deleted',
                    \("seller_phones && '{".$search_phones->join(',')."}'")
                ],
                db => $db,
            );
        }

        $db->commit;
        1;
    } or do {
        $db->rollback;
        if ($@ =~ /\Qphone_num_uniq_idx\E/) {
            return $self->render(json => {status => 'failed', errors => [{field => 'phone_num', msg => 'Duplicate phone num'}]});
        } else {
            return $self->render(json => {status => 'failed'});
        }
    };

    return $self->render(json => {status => 'success', num_realty_deleted => $num_realty_deleted, update_company_list => $update_company_list});
}

sub delete {
    my $self = shift;

    my $id = $self->param('id');

    my $num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {status => 'failed'}) unless $num_rows_updated;

    $self->render(json => {status => 'success'});
}

1;
