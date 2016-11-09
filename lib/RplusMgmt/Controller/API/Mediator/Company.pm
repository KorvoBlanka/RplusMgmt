package RplusMgmt::Controller::API::Mediator::Company;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Util::History qw(mediator_record);

use Mojo::Util qw(trim);

sub list {
    my $self = shift;
    my $acc_id = $self->session('account')->{id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'read');

    my ($name_filter, $phone_filter);
    if (my $filter = $self->param('filter')) {
        $filter = trim($filter);
        $filter =~ s/([%_])/\\$1/g;
        $name_filter = lc $filter;
        if ($filter =~ /^\+?\d{1,11}$/) {
            if ($filter =~ s/^8(.*)$/$1/) {} elsif ($filter =~ s/^\+7(.*)$/$1/) {}
            $phone_filter = $filter;
        }
    }

    # This code is used to fast counting of company phone numbers
    my $mediators_count = $self->db->dbh->selectall_hashref(q{
        SELECT MC.id, count(M.id) mediators_count
        FROM mediator_companies MC
        LEFT JOIN mediators M ON (M.company_id = MC.id AND M.delete_date IS NULL)
        WHERE MC.delete_date IS NULL
        GROUP BY MC.id
    }, 'id');

    my $res = {
        count => 0,
        list => [],
        phone_filter => $phone_filter,
    };

    my $condition = "AND (M.account_id IS NULL OR M.account_id = ".$acc_id.") AND (NOT M.hidden_for_aid && '{".$acc_id."}')";
    my @filter;
    if ($name_filter && $phone_filter) {
        push @filter, or => [
            [\'lower(name) LIKE ?' => lc($name_filter).'%'],
            [\('t1.id IN (SELECT M.company_id FROM mediators M WHERE M.delete_date IS NULL '.$condition.' AND M.phone_num LIKE ?)') => '%'.$phone_filter.'%'],
        ];
    } elsif ($name_filter) {
        push @filter, [\'lower(name) LIKE ?' => lc($name_filter).'%'];
    } elsif ($phone_filter) {
        push @filter, [\('t1.id IN (SELECT M.company_id FROM mediators M WHERE M.delete_date IS NULL '.$condition.' AND M.phone_num LIKE ?)') => '%'.$phone_filter.'%'];
    }

    my $company_iter = Rplus::Model::MediatorCompany::Manager->get_objects_iterator(
        query => [
            #or => [account_id => undef, account_id => $acc_id],
            #\("NOT t1.hidden_for_aid && '{".$acc_id."}'"),
            delete_date => undef,
            @filter
        ],
        sort_by => 'lower(name)'
    );
    while (my $company = $company_iter->next) {
        my $x = {
            id => $company->id,
            name => $company->name,
            mediators_count => $mediators_count->{$company->id}->{mediators_count},
        };
        push @{$res->{list}}, $x;
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'read');

    # Not Implemented

    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub save {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'write');

    # Retrieve company
    my $company;
    if (my $id = $self->param('id')) {
        $company = Rplus::Model::MediatorCompany::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        # We cannot create new companies here
        #$company = Rplus::Model::MediatorCompany->new;
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $company;

    # Validation
    $self->validation->required('name');

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {name => 'Invalid value'} if $self->validation->has_error('name');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Prepare data
    my $name = $self->param_n('name');

    mediator_record($acc_id, $user_id, 'update_company', $company, {
        name => $name
    });

    # Try to find existing company with the same name
    my $company_dst = Rplus::Model::MediatorCompany::Manager->get_objects(query => [[\'lower(t1.name) LIKE ?' => lc($name)], delete_date => undef])->[0];
    if ($company_dst && $company->id != $company_dst->id) {
        # Ok, move phones from src company to desctination company in transaction
        my $db = $self->db;
        $db->begin_work;

        # Move phones from the source company
        Rplus::Model::Mediator::Manager->update_objects(
            set => {company_id => $company_dst->id},
            where => [company_id => $company->id, delete_date => undef],
            db => $db,
        );

        # Delete source company
        Rplus::Model::MediatorCompany::Manager->update_objects(
            set => {delete_date => \'now()'},
            where => [id => $company->id],
            db => $db,
        );

        $db->commit;
        $company = $company_dst;
    } else {
        # Save
        $company->name($name);
        eval {
            $company->save;
            1;
        } or do {
            return $self->render(json => {error => $@}, status => 500);
        };
    }

    return $self->render(json => {status => 'success', id => $company->id});
}

sub delete {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};
    my $user_id = $self->stash('user')->{id};

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(mediators => 'write');

    my $id = $self->param('id');

    my $company = Rplus::Model::MediatorCompany::Manager->get_objects (query => [id => $id])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $company;

    my $hidden_for = Mojo::Collection->new(@{$company->hidden_for_aid});
    push @$hidden_for, ($acc_id);
    $company->hidden_for_aid($hidden_for->compact->uniq);
    $company->save(changes_only => 1);


    my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(
        query => [
            company_id => $id,
            delete_date => undef,
        ],
    );
    while (my $mediator = $mediator_iter->next) {
        my $hidden_for = Mojo::Collection->new(@{$mediator->hidden_for_aid});
        push @$hidden_for, ($acc_id);
        $mediator->hidden_for_aid($hidden_for->compact->uniq);
        $mediator->save(changes_only => 1);
    }

    mediator_record($acc_id, $user_id, 'delete_company', $company, undef);

    return $self->render(json => {status => 'success'});
}

1;
