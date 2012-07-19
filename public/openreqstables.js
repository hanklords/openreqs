      function initialise_table(nb_columns_to_merge) {

        var attributes_html= '<ul class="Attributes">\n';

        var ths=document.getElementsByTagName("th");
        for (var i=0;i<ths.length;i++){ 
          var th_class=ths[i].className;
          var th_text=ths[i].innerHTML;
          attributes_html+='<li class='+th_class+' style="display: none; "><a href="#"> '+th_text+' </a></li>\n';
        } 

        attributes_html+= '</ul>\n';
        $(document.body).append(attributes_html);

        $("th").append(" (<a class='hide' href='#'>hide</a>)");

        var trs=document.getElementsByTagName("tr");
        for(i = 2; i < trs.length; i++){
          var tds1=trs[i-1].getElementsByTagName("td");
          var tds2=trs[i].getElementsByTagName("td");
          var nb_source_val=0;
          if (nb_columns_to_merge>0){
            nb_source_val = nb_columns_to_merge + 2;
          }
          else {
            nb_source_val = 2;
          }
          if ((tds1[0].innerHTML) == (tds2[0].innerHTML)){
            for(j=0;j < nb_source_val;j++){
              tds2[j].style.fontSize="0px";
              tds2[j].style.borderTopStyle="hidden";
            }
          }
        }

        $("th a.hide").click(function(e) {
            e.preventDefault();
            var this_th = $(this).parents("th");
            var index = this_th.index() + 1;
            var attr_class = this_th.attr('class');

            this_th.hide();
            $("tr td:nth-child(" + index + ")").hide();
            $("li."+attr_class).show();
        });
        $("ul.Attributes li").click(function(e) {
            e.preventDefault();
            var attr_class = $(this).attr('class');
            var this_th = $(document).find("th."+attr_class);
            var index = this_th.index("th") + 1;

            this_th.show();
            $("tr td:nth-child(" + index + ")").show();
            $("li."+attr_class).hide();
        });
      }
