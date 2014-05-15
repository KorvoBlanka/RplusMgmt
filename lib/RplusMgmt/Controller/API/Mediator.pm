package RplusMgmt::Controller::API::Mediator;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Mojo::Collection;

sub list {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'read');

    my $company_id = $self->param('company_id');
    my $with_company = $self->param_b('with_company');

    my $res = {
        count => 0,
        list => [],
    };

    my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(
        query => [
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

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'write');

    # Retrieve mediator
    my $mediator;
    if (my $id = $self->param('id')) {
        $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [id => $id, delete_date => undef], require_objects => ['company'])->[0];
    } else {
        $mediator = Rplus::Model::Mediator->new;
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
                $company->save;
                $reload_company_list = 1;
            }
            $mediator->company($company);
        }

        $mediator->save;

        # Search for additional mediator phones
        my $found_phones = Mojo::Collection->new();
        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(select => 'id, owner_phones', query => ['!state_code' => 'deleted', \("owner_phones && '{".$phone_num."}'")], db => $db);
        while (my $realty = $realty_iter->next) {
            push @$found_phones, ($realty->owner_phones);
            $realty->mediator($company_name . ', ' . $name);
            $realty->agent_id(10000)->save;
            $self->realty_event('m', $realty->id);
        }
        $found_phones = $found_phones->uniq;

        my $realty_iter;
        
        if ($found_phones->size) {
            # Add additional mediators from realty owner phones
            for (@$found_phones) {
                if ($_ ne $phone_num && !Rplus::Model::Mediator::Manager->get_objects_count(query => [phone_num => $_, delete_date => undef], db => $db)) {
                    Rplus::Model::Mediator->new(db => $db, name => $name, phone_num => $_, company => $company)->save;
                }
            }

            #$num_realty_deleted = Rplus::Model::Realty::Manager->update_objects(
            #    set => {state_code => 'deleted', change_date => \'now()'},
            #    where => [
            #        '!state_code' => 'deleted',
            #        \("owner_phones && '{".$found_phones->join(',')."}'")
            #    ],
            #    db => $db,
            #);
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

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'write');

    my $id = $self->param('id');

    my $num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    $self->render(json => {status => 'success'});
}

1;
