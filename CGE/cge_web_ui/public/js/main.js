$(function() {
  'use strict';
  
  // Our fancy hamburger menu button
  $('.c-hamburger').on('click', function(e) {
    e.preventDefault();
    (this.classList.contains("is-active") === true) ? this.classList.remove("is-active") : this.classList.add("is-active");
    ($('#navigation').css('left') == '0px') ? $('#navigation').css('left','-500px') : $('#navigation').css('left','0px');
    ($('#content_area').css('left') == '0px') ? $('#content_area').css('left','500px') : $('#content_area').css('left','0px');
  });
  
  // Menu panel bar
  $('.ss_button').on('click', function() {
    $('.ss_content').slideUp();
    $(this).next('.ss_content').slideDown();
    console.log('clicked '+this);
  });
  
  /* Maybe do this differently later, but lets trigger a click so that the menu opens
     and the first menu item is exposed on page load */
  $('.c-hamburger').trigger('click');
  setTimeout(function() {
    $('#database_management').next('.ss_content').slideDown();
  },1000);
  
  
});