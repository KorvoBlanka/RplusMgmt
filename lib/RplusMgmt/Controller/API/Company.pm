package RplusMgmt::Controller::API::Company;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Company;
use Rplus::Model::Company::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;

use Rplus::DB;
use Mojo::Util qw(trim);

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'mediator'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $filter = $self->param('filter');
    if ($filter) {
        $filter =~ s/([%_])/\\$1/g;
        if ($filter =~ /^\+?\d{1,11}$/) {
            if ($filter =~ s/^8(.*)$/$1/) {} elsif ($filter =~ s/^\+7(.*)$/$1/) {}
        } else {
            $filter = lc($filter);
        }
    }
    my $limit = $self->param('limit') || 0;

    # Временное решение для _быстрого_ подсчета количества телефонов в компании
    my $_mediators_count = Rplus::DB->new->dbh->selectall_hashref(q{
        SELECT C.id, count(M.id) mediators_count
        FROM companies C
        LEFT JOIN mediators M ON (M.company_id = C.id AND M.delete_date IS NULL)
        WHERE C.delete_date IS NULL
        GROUP BY C.id
    }, 'id');

    my $res = {
        count => 0,
        list => [],
    };
    my $company_iter = Rplus::Model::Company::Manager->get_objects_iterator(
        query => [
            delete_date => undef,
            ($filter ? (
                or => [
                    name_lc => { like => $filter."%" },
                    ($filter =~ /^\d{1,10}$/ ? (
                        [ \'t1.id IN (SELECT M.company_id FROM mediators M WHERE M.delete_date IS NULL AND M.phone_num LIKE ?)' => '%'.$filter.'%' ]
                    ) : ()),
                ]
            ) : ()),
        ],
        ($limit ? (limit => $limit) : ()),
        sort_by => 'name',
    );
    while (my $company = $company_iter->next) {
        push @{$res->{'list'}}, {
            id => $company->id,
            name => $company->name,
            mediators_count => $_mediators_count->{$company->id}->{'mediators_count'},
        };
    }
    $res->{'count'} = @{$res->{'list'}};

    $self->render_json($res);
}

sub save {
    my $self = shift;

    my $id = $self->param('id');
    my $name = trim(scalar($self->param('name')));

    my $company = Rplus::Model::Company::Manager->get_objects(query => [ id => $id, delete_date => undef ])->[0] if $id;
    return $self->render_json({status => 'failed', errors => [{ msg => 'Invalid company id specified' }]}) unless $company;
    return $self->render_json({status => 'failed', errors => [{ field => 'name', msg => 'Empty company name' }]}) unless $name;

    # Выполним сохранение
    eval {
        $company->name($name);
        $company->save;
        1;
    } or do {
        if ($@ =~ /\Qcompanies_name_lc_uniq_idx\E/) {
            return $self->render_json({status => 'failed', errors => [{ field => 'name', msg => 'Duplicate company name' }]});
        } else {
            return $self->render_json({status => 'failed', errors => [{ msg => 'An error occurred' }]});
        }
    };

    $self->render_json({
        status => 'success',
        data => {
            id => $company->id,
            name => $company->name,
        }
    });
}

sub delete {
    my $self = shift;

    my $id = $self->param('id');
    return $self->render_json({status => 'failed'}) unless $id;

    # Удалим компанию
    my $num_rows_updated = Rplus::Model::Company::Manager->update_objects(
        set => { delete_date => \'now()' },
        where => [ id => $id, delete_date => undef ],
    );
    return $self->render_json({status => 'failed'}) unless $num_rows_updated;

    # Теперь удалим номера телефонов данной компании
    #   Реализовано в БД!
    #$num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
    #    set => { delete_date => \'now()' },
    #    where => [ company_id => $id, delete_date => undef ],
    #);

    $self->render_json({status => 'success'});
}

1;
