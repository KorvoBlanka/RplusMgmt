package Rplus::Util::Mediator;

use Rplus::Modern;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;

use Exporter qw(import);
 
our @EXPORT_OK = qw(delete_mediator add_mediator remove_obsolete_mediators);

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

    my $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(query => [delete_date => undef, \("owner_phones && '{".$mediator->phone_num."}'")]);
    while (my $realty = $realty_iter->next) {
        $realty->agent_id(undef);
        $realty->mediator_company_id(undef);
        $realty->save(changes_only => 1);
    }
    my $num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
}

sub add_mediator {
    # Prepare data
    my $company_name = shift;
    my $phone_num = shift;
    my $added_by = shift;

	my $mediator;
	if (Rplus::Model::Mediator::Manager->get_objects_count(query => [phone_num => $phone_num, delete_date => undef])) {
		$mediator = Rplus::Model::Mediator::Manager->get_objects(query => [phone_num => $phone_num, delete_date => undef])->[0];
	} else {
		$mediator = Rplus::Model::Mediator->new;
		$mediator->added_by($added_by);
	}

    $mediator->phone_num($phone_num);

    my $company = Rplus::Model::MediatorCompany::Manager->get_objects(query => [[\'lower(name) = ?' => lc($company_name)], delete_date => undef])->[0];
    unless ($company) {
        $company = Rplus::Model::MediatorCompany->new(name => $company_name);
        $company->save;
    }
    $mediator->company_id($company->id);
    $mediator->save;

    # Search for additional mediator phones
    my $found_phones = Mojo::Collection->new();
    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(query => [delete_date => undef, \("owner_phones && '{".$phone_num."}'")]);
    while (my $realty = $realty_iter->next) {
        $realty->agent_id(10000);
        $realty->state_code('raw') if $realty->state_code eq 'work';
        $realty->mediator_company_id($mediator->company->id);
        $realty->save(changes_only => 1);
        push @$found_phones, ($realty->owner_phones);
    }
    $found_phones = $found_phones->uniq;

    if ($found_phones->size) {
        # Add additional mediators from realty owner phones
        for (@$found_phones) {
            if ($_ ne $phone_num && !Rplus::Model::Mediator::Manager->get_objects_count(query => [phone_num => $_, delete_date => undef])) {
                my $nm = Rplus::Model::Mediator->new(phone_num => $_, company => $company, added_by => $added_by);
                $nm->save;
            }
        }
    }
}

1;
