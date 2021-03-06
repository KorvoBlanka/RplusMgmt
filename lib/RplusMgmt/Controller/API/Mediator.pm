package RplusMgmt::Controller::API::Mediator;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::History qw(mediator_record);

use Mojo::Collection;

sub list {
    my $self = shift;
    my $acc_id = $self->session('account')->{id};
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'read');

    my $company_id = $self->param('company_id');
    my $with_company = $self->param_b('with_company');

    my $res = {
        count => 0,
        list => [],
    };

    my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(
        query => [
            or => [account_id => undef, account_id => $acc_id],
            \("NOT t1.hidden_for_aid && '{".$acc_id."}'"),
            ($company_id ? (company_id => $company_id) : ()),
            delete_date => undef,
        ],
        sort_by => 'phone_num',
        require_objects => ['company'],
    );
    while (my $mediator = $mediator_iter->next) {
        my $x = {
            id => $mediator->id,
            name => $mediator->name,
            phone_num => $mediator->phone_num,
            company_id => $mediator->company_id,
            ($with_company ? (company => {map { $_ => $mediator->company->$_ } qw(id name)}) : ()),
        };
        push @{$res->{list}}, $x;
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub get {
    my $self = shift;
    my $acc_id = $self->session('account')->{id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'read');

    my $mediator;
    if (my $id = $self->param('id')) {
        $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [id => $id, delete_date => undef], require_objects => ['company'])->[0];
    } elsif (my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'))) {
        $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef], require_objects => ['company'])->[0];
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $mediator;

    my $res = {
        id => $mediator->id,
        name => $mediator->name,
        phone_num => $mediator->phone_num,
        company_id => $mediator->company_id,
        company => {map { $_ => $mediator->company->$_ } qw(id name)},
    };

    return $self->render(json => $res);
}

sub save {
    my $self = shift;
    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'write');

    # Retrieve mediator
    my $mediator;
    if (my $id = $self->param('id')) {
        $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [id => $id, delete_date => undef], require_objects => ['company'])->[0];
    } else {
        $mediator = Rplus::Model::Mediator->new;
        $mediator->account_id($acc_id);
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $mediator;

    # Validation
    $self->validation->required('company_name');
    $self->validation->required('phone_num')->is_phone_num;

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {company_name => 'Invalid value'} if $self->validation->has_error('company_name');
        push @errors, {phone_num => 'Invalid value'} if $self->validation->has_error('phone_num');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Prepare data
    my $company_name = $self->param_n('company_name');
    my $name = $self->param_n('name');
    my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'));

    # Begin transaction
    my $db = $self->db;
    $db->begin_work;

    if ($mediator->id) {
        mediator_record($user_id, 'update', $mediator, {
            name => $name,
            phone_num => $phone_num
        });
    }

    $mediator->db($db);
    $mediator->name($name);
    $mediator->phone_num($phone_num);

    my ($num_realty_deleted, $reload_company_list) = (0, 0);
    eval {
        my $company = $mediator->company;
        if (!$company || lc($company->name) ne lc($company_name)) {
            # Add new company or move mediator to another company
            $company = Rplus::Model::MediatorCompany::Manager->get_objects(query => [[\'lower(name) = ?' => lc($company_name)], delete_date => undef], db => $db)->[0];
            if (!$company) {
                $company = Rplus::Model::MediatorCompany->new(name => $company_name, db => $db);
                $company->account_id($acc_id);
                $company->save;
                mediator_record($user_id, 'add_company', $company, undef);
                $reload_company_list = 1;
            }
            $mediator->company($company);
        }

        unless ($mediator->id) {
            $mediator->save(insert => 1);
            mediator_record($user_id, 'add', $mediator, undef);
        } else {
            $mediator->save(changes_only => 1);
        }

        # Search for additional mediator phones
        my $found_phones = Mojo::Collection->new();
        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(query => [delete_date => undef, \("owner_phones && '{".$phone_num."}'")], db => $db);
        while (my $realty = $realty_iter->next) {
            push @$found_phones, ($realty->owner_phones);
        }
        $found_phones = $found_phones->uniq;

        if ($found_phones->size) {
            # Add additional mediators from realty owner phones
            for (@$found_phones) {
                if ($_ ne $phone_num && !Rplus::Model::Mediator::Manager->get_objects_count(query => [phone_num => $_, delete_date => undef], db => $db)) {
                    Rplus::Model::Mediator->new(db => $db, name => $name, phone_num => $_, company => $company, account_id => $acc_id,)->save;
                }
            }
        }

        $db->commit;
        1;
    } or do {
        $db->rollback;
        if ($@ =~ /\Qphone_num_uniq_idx\E/) {
            return $self->render(json => {errors => [{phone_num => 'Duplicate phone num'}]}, status => 400);
        } else {
            return $self->render(json => {error => $@}, status => 500);
        }
    };

    return $self->render(json => {status => 'success', num_realty_deleted => $num_realty_deleted, reload_company_list => $reload_company_list});
}

sub get_obj_count {
    my $self = shift;
    my $id = $self->param('id');
    my $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    my $realty_count = Rplus::Model::Realty::Manager->get_objects_count(query => [delete_date => undef, \("owner_phones && '{".$mediator->phone_num."}'")]);

    return $self->render(json => {count => $realty_count, status => 'success'});
}

sub delete {
    my $self = shift;
    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'write');

    my $id = $self->param('id');

    #return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    my $found_phones = Mojo::Collection->new();
    my $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];

    my $hidden_for = Mojo::Collection->new(@{$mediator->hidden_for_aid});
    push @$hidden_for, ($acc_id);
    $mediator->hidden_for_aid($hidden_for->compact->uniq);
    $mediator->save(changes_only => 1);

    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(query => [delete_date => undef, \("owner_phones && '{".$mediator->phone_num."}'")]);
    while (my $realty = $realty_iter->next) {
        push @$found_phones, ($realty->owner_phones);
    }

    $found_phones = $found_phones->uniq;

    mediator_record($user_id, 'delete', $mediator, undef);

    $self->render(json => {status => 'success'});
}

1;
