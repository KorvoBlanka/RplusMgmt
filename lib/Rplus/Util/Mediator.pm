package Rplus::Util::Mediator;

use Rplus::Modern;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;

use Exporter qw(import);

our @EXPORT_OK = qw(delete_mediator delete_mediator_by_phone add_mediator remove_obsolete_mediators);

sub remove_obsolete_mediators {
    my $obs_period = shift;
    my $num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [
            '!added_by' => 'buffer',
            [\"last_seen_date < (NOW() - INTERVAL '$obs_period day')"],
            delete_date => undef],
    );

    return $num_rows_updated;
}

sub delete_mediator {
    my $id = shift;
    my $num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
}

sub delete_mediator_by_phone {
    my $phone_num = shift;

    my $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef])->[0];
    return unless $mediator;

    my $num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $mediator->id, delete_date => undef],
    );
}

sub add_mediator {
    # Prepare data
    my $company_name = shift;
    my $phone_num = shift;
    my $added_by = shift;
    my $acc_id = shift;

    unless ($added_by) {
        $added_by = 'system';
    }

    my $mediator;
    if ($acc_id) {
        $mediator = Rplus::Model::Mediator::Manager->get_objects(
            query => [
                phone_num => $phone_num,
                account_id => $acc_id,
                delete_date => undef,
                \("NOT t1.hidden_for_aid && '{".$acc_id."}'"),
            ]
        )->[0];
    } else {
      $mediator = Rplus::Model::Mediator::Manager->get_objects(
          query => [
              phone_num => $phone_num,
              account_id => undef,
              delete_date => undef,
          ]
      )->[0];
    }

  	unless ($mediator) {
  		$mediator = Rplus::Model::Mediator->new(phone_num => $phone_num, added_by => $added_by, account_id => $acc_id);
  	}

    my $company = Rplus::Model::MediatorCompany::Manager->get_objects(query => [[\'lower(name) = ?' => lc($company_name)], delete_date => undef])->[0];
    unless ($company) {
        $company = Rplus::Model::MediatorCompany->new(name => $company_name, account_id => $acc_id,);
        $company->save;
    }
    $mediator->company_id($company->id);
    $mediator->save;

    # Search for additional mediator phones
    my @fp = ();
    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(query => [delete_date => undef, \("owner_phones && '{".$phone_num."}'")]);
    while (my $realty = $realty_iter->next) {
        push @fp, @{$realty->owner_phones};
    }
    my $found_phones = Mojo::Collection->new(@fp)->compact->uniq;

    # Add additional mediators from realty owner phones
    $found_phones->each(sub {
        if ($_ ne $phone_num && !Rplus::Model::Mediator::Manager->get_objects_count(query => [phone_num => $_, delete_date => undef])) {
            my $nm = Rplus::Model::Mediator->new(phone_num => $_, company_id => $company->id, added_by => $added_by);
            $nm->save;
        }
    });
}

1;
