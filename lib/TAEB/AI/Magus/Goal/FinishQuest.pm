package TAEB::AI::Magus::Goal::FinishQuest;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'EnterQuest', 'QuestExperience' }

sub met_when { TAEB->seen_artifact('Bell of Opening') }

1;

