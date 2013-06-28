package TAEB::AI::Magus::Goal::EnterQuest;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

# QuestExperience not actually needed to enter the quest portal
# We want those wraiths to help us get XL14
# sub prerequisite_goals { 'QuestExperience' }

sub met_when {
    my $branch = TAEB->current_level->branch;
    return ($branch || '') eq 'Quest';
}

1;

